import AetherEngine
import Foundation

struct JellyfinPlaybackPlan: Sendable {
    let item: JellyfinItem
    let url: URL
    let headers: [String: String]
    let mediaSourceID: String
    let playSessionID: String
    let initialPosition: TimeInterval?
    let preferredAudioStreamIndex: Int?
    let preferredSubtitleStreamIndex: Int?
    let subtitleSelectionIsOff: Bool
    let mediaStreams: [JellyfinMediaStream]
    let chapters: [JellyfinChapter]
    let externalSubtitles: [ExternalSubtitleTrack]
    let method: PlaybackMethod
    let playMethod: String
    let requestedQuality: TranscodeQualityPreset
    let effectiveQuality: TranscodeQualityPreset
    let qualityFallbackMessage: String?
}

enum JellyfinSubtitleStreamPreference: Sendable {
    case serverDefault
    case off
    case stream(Int)

    var requestIndex: Int? {
        switch self {
        case .serverDefault: nil
        case .off: -1
        case let .stream(index): index
        }
    }
}

struct JellyfinTrackSelectionOverride: Sendable {
    var audioStreamIndex: Int?
    var subtitlePreference: JellyfinSubtitleStreamPreference = .serverDefault
}

@MainActor
struct JellyfinPlaybackService {
    private let context: JellyfinAPIContext

    init(context: JellyfinAPIContext) {
        self.context = context
    }

    func prepare(
        item: JellyfinItem,
        resume: Bool = true,
        trackSelection: JellyfinTrackSelectionOverride? = nil,
        trackPreference: MediaTrackPreference? = nil,
        quality: TranscodeQualityPreset = .original,
    ) async throws -> JellyfinPlaybackPlan {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }

        var appliedTrackSelection = trackSelection ?? initialTrackSelection(for: trackPreference)
        var info = try await requestPlaybackInfo(
            item: item,
            userID: userID,
            resume: resume,
            trackSelection: appliedTrackSelection,
            quality: quality,
        )

        guard info.errorCode == nil,
              let source = preferredSource(in: info, quality: quality),
              let playSessionID = info.playSessionID,
              !playSessionID.isEmpty
        else {
            throw JellyfinAPIError.noPlayableSource
        }

        let streams = source.mediaStreams ?? []

        if trackSelection == nil,
           let trackPreference,
           let resolvedSelection = resolveTrackSelection(trackPreference, source: source),
           resolvedSelection.audioStreamIndex != nil
               || resolvedSelection.subtitlePreference.requestIndex != nil
               || isSubtitleOff(resolvedSelection.subtitlePreference)
        {
            info = try await requestPlaybackInfo(
                item: item,
                userID: userID,
                resume: resume,
                trackSelection: resolvedSelection,
                quality: quality,
            )
            appliedTrackSelection = resolvedSelection
        }

        guard let resolvedSource = preferredSource(in: info, quality: quality) else {
            throw JellyfinAPIError.noPlayableSource
        }
        guard let resolvedPlaySessionID = info.playSessionID, !resolvedPlaySessionID.isEmpty else {
            throw JellyfinAPIError.noPlayableSource
        }
        let transcodeURL = resolvedSource.transcodingURL.flatMap {
            URL(string: $0, relativeTo: context.connection?.baseURL)?.absoluteURL
        }
        let isTranscoding = !quality.isOriginal && transcodeURL != nil
        let qualityIsSatisfied = quality.isOriginal
            || isTranscoding
            || sourceSatisfies(resolvedSource, quality: quality)
        let streamURL = if let transcodeURL, isTranscoding {
            transcodeURL
        } else {
            try context.url(
                path: ["Videos", item.id, "stream"],
                query: [
                    URLQueryItem(name: "Static", value: "true"),
                    URLQueryItem(name: "MediaSourceId", value: resolvedSource.id),
                    URLQueryItem(name: "PlaySessionId", value: resolvedPlaySessionID),
                ],
            )
        }
        let headers = try context.playbackHeaders()
        let effectiveStreams = resolvedSource.mediaStreams ?? streams
        let effectiveAudioStreams = effectiveStreams.filter { $0.type.lowercased() == "audio" }
        let effectiveSubtitleStreams = effectiveStreams.filter { $0.type.lowercased() == "subtitle" }
        let selectedAudioStreamIndex = appliedTrackSelection?.audioStreamIndex.flatMap { selectedIndex in
            effectiveAudioStreams.contains(where: { $0.index == selectedIndex }) ? selectedIndex : nil
        } ?? trackPreference.flatMap { resolveAudioStream($0, streams: effectiveAudioStreams)?.index }
            ?? defaultAudioStreamIndex(source: resolvedSource, streams: effectiveAudioStreams)
        let selectedSubtitleStreamIndex: Int? = switch appliedTrackSelection?.subtitlePreference {
        case .off:
            nil
        case let .stream(selectedIndex):
            effectiveSubtitleStreams.contains(where: { $0.index == selectedIndex })
                ? selectedIndex
                : defaultSubtitleStreamIndex(source: resolvedSource, streams: effectiveSubtitleStreams)
        case .serverDefault, nil:
            if appliedTrackSelection == nil, let trackPreference,
               case .track = trackPreference.subtitle,
               let preferred = resolveSubtitleStream(trackPreference, streams: effectiveSubtitleStreams)
            {
                preferred.index
            } else {
                defaultSubtitleStreamIndex(source: resolvedSource, streams: effectiveSubtitleStreams)
            }
        }
        let externalSubtitles = externalSubtitles(streams: streams, headers: headers)

        return JellyfinPlaybackPlan(
            item: item,
            url: streamURL,
            headers: headers,
            mediaSourceID: resolvedSource.id,
            playSessionID: resolvedPlaySessionID,
            initialPosition: resume ? item.resumePosition : nil,
            preferredAudioStreamIndex: selectedAudioStreamIndex,
            preferredSubtitleStreamIndex: selectedSubtitleStreamIndex,
            subtitleSelectionIsOff: isSubtitleOff(appliedTrackSelection?.subtitlePreference),
            mediaStreams: effectiveStreams,
            chapters: item.chapters ?? [],
            externalSubtitles: externalSubtitles,
            method: isTranscoding ? .transcode : .directPlay,
            playMethod: isTranscoding ? "Transcode" : "DirectPlay",
            requestedQuality: quality,
            effectiveQuality: qualityIsSatisfied ? quality : .original,
            qualityFallbackMessage: !qualityIsSatisfied
                ? String(localized: "player.quality.fallback")
                : nil,
        )
    }

    private func requestPlaybackInfo(
        item: JellyfinItem,
        userID: String,
        resume: Bool,
        trackSelection: JellyfinTrackSelectionOverride?,
        quality: TranscodeQualityPreset,
    ) async throws -> JellyfinPlaybackInfo {
        let body = JellyfinPlaybackInfoRequest(
            userID: userID,
            startTimeTicks: resume ? (item.userData?.playbackPositionTicks ?? 0) : 0,
            audioStreamIndex: trackSelection?.audioStreamIndex,
            subtitleStreamIndex: trackSelection?.subtitlePreference.requestIndex,
            quality: quality,
            deviceProfile: .strimr(quality: quality),
        )
        return try await context.post(
            path: ["Items", item.id, "PlaybackInfo"],
            query: [URLQueryItem(name: "UserId", value: userID)],
            body: body,
        )
    }

    private func initialTrackSelection(for preference: MediaTrackPreference?) -> JellyfinTrackSelectionOverride? {
        guard let preference else { return nil }
        if case .off = preference.subtitle {
            return JellyfinTrackSelectionOverride(
                audioStreamIndex: nil,
                subtitlePreference: .off,
            )
        }
        return nil
    }

    private func resolveTrackSelection(
        _ preference: MediaTrackPreference,
        source: JellyfinMediaSource,
    ) -> JellyfinTrackSelectionOverride? {
        let streams = source.mediaStreams ?? []
        let audio = resolveAudioStream(preference, streams: streams.filter { $0.type.lowercased() == "audio" })
        let subtitle: JellyfinSubtitleStreamPreference = switch preference.subtitle {
        case .serverDefault:
            .serverDefault
        case .off:
            .off
        case .track:
            resolveSubtitleStream(preference, streams: streams.filter { $0.type.lowercased() == "subtitle" })
                .map { .stream($0.index) } ?? .serverDefault
        }
        guard audio != nil || subtitle.requestIndex != nil || isSubtitleOff(subtitle) else { return nil }
        return JellyfinTrackSelectionOverride(
            audioStreamIndex: audio?.index,
            subtitlePreference: subtitle,
        )
    }

    private func resolveAudioStream(
        _ preference: MediaTrackPreference,
        streams: [JellyfinMediaStream],
    ) -> JellyfinMediaStream? {
        if let index = preference.audioStreamIndex,
           let exact = streams.first(where: { $0.index == index })
        {
            return exact
        }
        let candidates = streams.filter { stream in
            guard let language = preference.audioLanguage else { return true }
            return normalized(stream.language) == normalized(language)
        }
        guard preference.audioLanguage != nil || preference.audioTitle != nil || preference.audioCodec != nil else {
            return nil
        }
        return candidates
            .map { stream in
                (stream, audioMatchScore(stream, preference: preference))
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }

    private func resolveSubtitleStream(
        _ preference: MediaTrackPreference,
        streams: [JellyfinMediaStream],
    ) -> JellyfinMediaStream? {
        guard case let .track(index, language, title, codec, isForced, isHearingImpaired) = preference.subtitle else {
            return nil
        }
        if let index, let exact = streams.first(where: { $0.index == index }) {
            return exact
        }
        let candidates = streams.filter { stream in
            guard let language else { return true }
            return normalized(stream.language) == normalized(language)
        }
        guard language != nil || title != nil || !codec.isEmpty else { return nil }
        return candidates
            .map { stream in
                (stream, subtitleMatchScore(
                    stream,
                    language: language,
                    title: title,
                    codec: codec,
                    isForced: isForced,
                    isHearingImpaired: isHearingImpaired,
                ))
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }

    private func audioMatchScore(
        _ stream: JellyfinMediaStream,
        preference: MediaTrackPreference,
    ) -> Int {
        var score = 0
        if let language = preference.audioLanguage, normalized(stream.language) == normalized(language) { score += 4 }
        if let title = preference.audioTitle, normalized(stream.displayTitle ?? stream.title) == normalized(title) { score += 3 }
        if let codec = preference.audioCodec, normalized(stream.codec) == normalized(codec) { score += 2 }
        if let hearingImpaired = preference.audioIsHearingImpaired,
           stream.isHearingImpaired == hearingImpaired
        { score += 1 }
        return score
    }

    private func subtitleMatchScore(
        _ stream: JellyfinMediaStream,
        language: String?,
        title: String?,
        codec: String,
        isForced: Bool,
        isHearingImpaired: Bool?,
    ) -> Int {
        var score = 0
        if let language, normalized(stream.language) == normalized(language) { score += 4 }
        if let title, normalized(stream.displayTitle ?? stream.title) == normalized(title) { score += 3 }
        if !codec.isEmpty, normalized(stream.codec) == normalized(codec) { score += 2 }
        if stream.isForced == isForced { score += 1 }
        if let isHearingImpaired, stream.isHearingImpaired == isHearingImpaired { score += 1 }
        return score
    }

    private func isSubtitleOff(_ preference: JellyfinSubtitleStreamPreference?) -> Bool {
        if case .off = preference { return true }
        return false
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private func sourceSatisfies(
        _ source: JellyfinMediaSource,
        quality: TranscodeQualityPreset,
    ) -> Bool {
        guard let maximumBitrate = quality.jellyfinMaximumStreamingBitrate,
              let maximumWidth = quality.maximumWidth,
              let maximumHeight = quality.maximumHeight,
              let video = source.mediaStreams?.first(where: { $0.type.lowercased() == "video" }),
              let width = video.width,
              let height = video.height
        else { return false }

        let streamBitrates = source.mediaStreams?.compactMap(\.bitrate) ?? []
        let sourceBitrate = source.bitrate ?? (streamBitrates.isEmpty ? nil : streamBitrates.reduce(0, +))
        guard let sourceBitrate else { return false }
        return sourceBitrate <= maximumBitrate
            && width <= maximumWidth
            && height <= maximumHeight
    }

    private func preferredSource(
        in info: JellyfinPlaybackInfo,
        quality: TranscodeQualityPreset,
    ) -> JellyfinMediaSource? {
        if !quality.isOriginal,
           let transcoding = info.mediaSources?.first(where: { $0.transcodingURL?.isEmpty == false })
        {
            return transcoding
        }
        return info.mediaSources?.first(where: { $0.supportsDirectPlay == true })
            ?? info.mediaSources?.first
    }

    private func defaultSubtitleStreamIndex(
        source: JellyfinMediaSource,
        streams: [JellyfinMediaStream],
    ) -> Int? {
        source.defaultSubtitleStreamIndex.flatMap { defaultIndex in
            streams.contains(where: { $0.index == defaultIndex }) ? defaultIndex : nil
        } ?? streams.first(where: { $0.isDefault == true })?.index
    }

    private func defaultAudioStreamIndex(
        source: JellyfinMediaSource,
        streams: [JellyfinMediaStream],
    ) -> Int? {
        source.defaultAudioStreamIndex.flatMap { defaultIndex in
            streams.contains(where: { $0.index == defaultIndex }) ? defaultIndex : nil
        } ?? streams.first(where: { $0.isDefault == true })?.index ?? streams.first?.index
    }

    func externalSubtitles(item: JellyfinItem) throws -> [ExternalSubtitleTrack] {
        let headers = try context.playbackHeaders()
        return externalSubtitles(
            streams: (item.mediaSources ?? []).flatMap { $0.mediaStreams ?? [] },
            headers: headers,
        )
    }

    private func externalSubtitles(
        streams: [JellyfinMediaStream],
        headers: [String: String],
    ) -> [ExternalSubtitleTrack] {
        streams.compactMap { stream -> ExternalSubtitleTrack? in
            guard stream.type.lowercased() == "subtitle",
                  stream.isExternal == true,
                  stream.deliveryMethod?.lowercased() == "external",
                  let deliveryURL = stream.deliveryURL,
                  let url = URL(string: deliveryURL, relativeTo: context.connection?.baseURL)?.absoluteURL
            else {
                return nil
            }
            return ExternalSubtitleTrack(
                url: url,
                name: stream.displayTitle,
                language: stream.language,
                isForced: stream.isForced ?? false,
                isDefault: stream.isDefault ?? false,
                httpHeaders: headers,
                formatHint: stream.codec,
            )
        }
    }

    func reportStarted(
        plan: JellyfinPlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        try await sendReport(
            path: ["Sessions", "Playing"],
            plan: plan,
            position: position,
            isPaused: isPaused,
            currentSelection: currentSelection,
        )
    }

    func reportProgress(
        plan: JellyfinPlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        try await sendReport(
            path: ["Sessions", "Playing", "Progress"],
            plan: plan,
            position: position,
            isPaused: isPaused,
            currentSelection: currentSelection,
        )
    }

    func reportStopped(
        plan: JellyfinPlaybackPlan,
        position: TimeInterval,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        let body = JellyfinPlaybackReport(
            itemID: plan.item.id,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: JellyfinTime.ticks(fromSeconds: position),
            isPaused: true,
            playMethod: plan.playMethod,
            currentSelection: currentSelection,
        )
        let data = try JSONEncoder().encode(body)
        try await context.send(path: ["Sessions", "Playing", "Stopped"], method: "POST", body: data)
    }

    private func sendReport(
        path: [String],
        plan: JellyfinPlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws {
        let body = JellyfinPlaybackReport(
            itemID: plan.item.id,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: JellyfinTime.ticks(fromSeconds: position),
            isPaused: isPaused,
            playMethod: plan.playMethod,
            currentSelection: currentSelection,
        )
        let data = try JSONEncoder().encode(body)
        try await context.send(path: path, method: "POST", body: data)
    }
}

private struct JellyfinPlaybackInfoRequest: Encodable {
    let userID: String
    let startTimeTicks: Int64
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let isPlayback = true
    let autoOpenLiveStream = true
    let enableDirectPlay = true
    let enableDirectStream = false
    let enableTranscoding: Bool
    let maxStreamingBitrate: Int
    let deviceProfile: JellyfinDeviceProfile

    init(
        userID: String,
        startTimeTicks: Int64,
        audioStreamIndex: Int?,
        subtitleStreamIndex: Int?,
        quality: TranscodeQualityPreset,
        deviceProfile: JellyfinDeviceProfile,
    ) {
        self.userID = userID
        self.startTimeTicks = startTimeTicks
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        enableTranscoding = !quality.isOriginal
        maxStreamingBitrate = quality.jellyfinMaximumStreamingBitrate ?? 140_000_000
        self.deviceProfile = deviceProfile
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case startTimeTicks = "StartTimeTicks"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case isPlayback = "IsPlayback"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case deviceProfile = "DeviceProfile"
    }
}

struct JellyfinDeviceProfile: Encodable {
    let name: String
    let maxStreamingBitrate: Int
    let maxStaticBitrate: Int
    let directPlayProfiles: [DirectPlayProfile]
    let transcodingProfiles: [TranscodingProfile]
    let containerProfiles: [EmptyProfile]
    let codecProfiles: [CodecProfile]
    let subtitleProfiles: [SubtitleProfile]
    let responseProfiles: [EmptyProfile]

    struct DirectPlayProfile: Encodable {
        let container: String
        let audioCodec: String
        let videoCodec: String
        let type: String

        private enum CodingKeys: String, CodingKey {
            case container = "Container"
            case audioCodec = "AudioCodec"
            case videoCodec = "VideoCodec"
            case type = "Type"
        }
    }

    struct SubtitleProfile: Encodable {
        let format: String
        let method: String

        private enum CodingKeys: String, CodingKey {
            case format = "Format"
            case method = "Method"
        }
    }

    struct TranscodingProfile: Encodable {
        let container: String
        let type: String
        let videoCodec: String
        let audioCodec: String
        let protocolName: String

        private enum CodingKeys: String, CodingKey {
            case container = "Container"
            case type = "Type"
            case videoCodec = "VideoCodec"
            case audioCodec = "AudioCodec"
            case protocolName = "Protocol"
        }
    }

    struct CodecProfile: Encodable {
        let type: String
        let codec: String
        let conditions: [ProfileCondition]

        private enum CodingKeys: String, CodingKey {
            case type = "Type"
            case codec = "Codec"
            case conditions = "Conditions"
        }
    }

    struct ProfileCondition: Encodable {
        let condition: String
        let property: String
        let value: String
        let isRequired: Bool

        private enum CodingKeys: String, CodingKey {
            case condition = "Condition"
            case property = "Property"
            case value = "Value"
            case isRequired = "IsRequired"
        }
    }

    struct EmptyProfile: Encodable {}

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case maxStaticBitrate = "MaxStaticBitrate"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case containerProfiles = "ContainerProfiles"
        case codecProfiles = "CodecProfiles"
        case subtitleProfiles = "SubtitleProfiles"
        case responseProfiles = "ResponseProfiles"
    }

    static func strimr(quality: TranscodeQualityPreset) -> JellyfinDeviceProfile {
        let maxBitrate = quality.jellyfinMaximumStreamingBitrate ?? 140_000_000
        return JellyfinDeviceProfile(
            name: quality.isOriginal ? "Strimr Direct Play" : "Strimr Quality Transcode",
            maxStreamingBitrate: maxBitrate,
            maxStaticBitrate: maxBitrate,
            directPlayProfiles: [
                DirectPlayProfile(
                    container: "mp4,m4v,mov,mkv,webm,avi,mpegts,ts,m2ts",
                    audioCodec: "aac,ac3,eac3,truehd,dts,flac,opus,vorbis,mp3,alac,pcm_s16le,pcm_s24le",
                    videoCodec: "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,vc1",
                    type: "Video",
                ),
            ],
            transcodingProfiles: quality.isOriginal ? [] : [
                TranscodingProfile(
                    container: "ts",
                    type: "Video",
                    videoCodec: "hevc,h264",
                    audioCodec: "aac,mp3,ac3,eac3,flac,opus",
                    protocolName: "hls",
                ),
            ],
            containerProfiles: [],
            codecProfiles: quality.jellyfinResolutionCodecProfiles,
            subtitleProfiles: [
                SubtitleProfile(format: "srt", method: "External"),
                SubtitleProfile(format: "ass", method: "External"),
                SubtitleProfile(format: "ssa", method: "External"),
                SubtitleProfile(format: "vtt", method: "External"),
                SubtitleProfile(format: "subrip", method: "Embed"),
                SubtitleProfile(format: "ass", method: "Embed"),
                SubtitleProfile(format: "pgssub", method: "Embed"),
                SubtitleProfile(format: "dvdsub", method: "Embed"),
            ],
            responseProfiles: [],
        )
    }

    static func liveTV() -> JellyfinDeviceProfile {
        JellyfinDeviceProfile(
            name: "Strimr Live TV",
            maxStreamingBitrate: 120_000_000,
            maxStaticBitrate: 100_000_000,
            directPlayProfiles: [
                DirectPlayProfile(
                    container: "hls,mp4,m4v,mov,mkv,webm,ts,mpegts,m2ts",
                    audioCodec: "aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts",
                    videoCodec: "h264,hevc,h265,vp8,vp9,av1,mpeg4,mpeg2video",
                    type: "Video",
                ),
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    container: "ts",
                    type: "Video",
                    videoCodec: "hevc,h264",
                    audioCodec: "aac,mp3,mp2,ac3,eac3,flac,opus",
                    protocolName: "hls",
                ),
            ],
            containerProfiles: [],
            codecProfiles: [],
            subtitleProfiles: [
                SubtitleProfile(format: "vtt", method: "External"),
                SubtitleProfile(format: "ass", method: "External"),
                SubtitleProfile(format: "ssa", method: "External"),
            ],
            responseProfiles: [],
        )
    }
}

private extension TranscodeQualityPreset {
    static let jellyfinAudioOverheadKbps = 192

    var jellyfinMaximumStreamingBitrate: Int? {
        maximumVideoBitrateKbps.map {
            ($0 + Self.jellyfinAudioOverheadKbps) * 1000
        }
    }

    var jellyfinResolutionCodecProfiles: [JellyfinDeviceProfile.CodecProfile] {
        guard let maximumWidth, let maximumHeight else { return [] }
        return [
            JellyfinDeviceProfile.CodecProfile(
                type: "Video",
                codec: "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,vc1",
                conditions: [
                    JellyfinDeviceProfile.ProfileCondition(
                        condition: "LessThanEqual",
                        property: "Width",
                        value: String(maximumWidth),
                        isRequired: false,
                    ),
                    JellyfinDeviceProfile.ProfileCondition(
                        condition: "LessThanEqual",
                        property: "Height",
                        value: String(maximumHeight),
                        isRequired: false,
                    ),
                ],
            ),
        ]
    }
}

private struct JellyfinPlaybackReport: Encodable {
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    let positionTicks: Int64
    let isPaused: Bool
    let playMethod: String
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let canSeek = true
    let isMuted = false
    let repeatMode = "RepeatNone"

    private enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playMethod = "PlayMethod"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case canSeek = "CanSeek"
        case isMuted = "IsMuted"
        case repeatMode = "RepeatMode"
    }

    init(
        itemID: String,
        mediaSourceID: String,
        playSessionID: String,
        positionTicks: Int64,
        isPaused: Bool,
        playMethod: String,
        currentSelection: PlaybackStreamSelection?,
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.positionTicks = positionTicks
        self.isPaused = isPaused
        self.playMethod = playMethod
        audioStreamIndex = currentSelection?.audioStreamIndex
        subtitleStreamIndex = if let currentSelection {
            currentSelection.subtitleIsOff ? -1 : currentSelection.subtitleStreamIndex
        } else {
            nil
        }
    }
}
