import Foundation

@MainActor
final class PlexLiveTVService: MediaLiveTVService, MediaDVRService {
    private struct EPGProvider {
        let id: String?
        let identifier: String
        let gridPath: String
    }

    private struct FavoriteChannelKey: Hashable {
        let source: String
        let providerID: String
    }

    private let context: PlexAPIContext
    private let network: PlexServerNetworkClient
    private var dvrs: [[String: Any]] = []
    private var providers: [EPGProvider] = []
    private var lastPrograms: [LiveTVProgram] = []

    init(context: PlexAPIContext) {
        self.context = context
        network = PlexServerNetworkClient(context: context)
    }

    var dvr: (any MediaDVRService)? {
        self
    }

    var supportsServerCaptureBuffer: Bool {
        true
    }

    var supportsCompletedRecordings: Bool {
        false
    }

    var canManageRecordings: Bool {
        true
    }

    var canDeleteRecordings: Bool {
        false
    }

    func isAvailable() async throws -> Bool {
        try await discover()
        return !dvrs.isEmpty
    }

    func channels() async throws -> [LiveTVChannel] {
        try await ensureDiscovered()
        let favorites = await (try? favoriteChannelKeys()) ?? []
        var result: [LiveTVChannel] = []
        for provider in providers {
            guard let dvrID = matchingDVRID(provider: provider) else { continue }
            let enabled = enabledChannelIDs(for: dvrID)
            let paths = provider.identifier.hasPrefix("tv.plex.providers.epg")
                ? ["/lineups/plex/channels", "/\(provider.identifier)/lineups/dvr/channels"]
                : ["/\(provider.identifier)/lineups/dvr/channels"]
            for path in paths {
                guard let root = try? await network.json(path: path),
                      let container = mediaContainer(root)
                else { continue }
                let raw = dictionaries(container["Channel"] ?? container["Metadata"])
                let parsed = raw.compactMap { item -> LiveTVChannel? in
                    let providerID = string(item["key"] ?? item["ratingKey"] ?? item["identifier"] ?? item["id"])
                    guard let providerID, !providerID.isEmpty else { return nil }
                    if let enabled, !enabled.contains(providerID) {
                        return nil
                    }
                    var channel = LiveTVChannel(
                        providerID: providerID,
                        title: string(item["title"] ?? item["callSign"]) ?? String(localized: "livetv.channel.unknown"),
                        callSign: string(item["callSign"]),
                        number: string(item["number"] ?? item["channelNumber"] ?? item["channelVcn"]),
                        thumbPath: string(item["thumb"]),
                        artPath: string(item["art"]),
                        lineupID: provider.identifier,
                        dvrID: dvrID,
                        isHD: bool(item["hd"]) ?? false,
                        isFavorite: false,
                    )
                    channel.isFavorite = favorites.contains(favoriteKey(for: channel))
                    return channel
                }
                result.append(contentsOf: parsed)
                if !parsed.isEmpty {
                    break
                }
            }
        }
        return unique(result).sorted(by: channelSort)
    }

    func programs(from: Date, to: Date) async throws -> [LiveTVProgram] {
        try await ensureDiscovered()
        var result: [LiveTVProgram] = []
        for provider in providers {
            guard let dvrID = matchingDVRID(provider: provider) else { continue }
            let root = try await network.json(
                path: provider.gridPath,
                queryItems: [
                    URLQueryItem(name: "endsAt>", value: String(Int(from.timeIntervalSince1970))),
                    URLQueryItem(name: "beginsAt<", value: String(Int(to.timeIntervalSince1970))),
                ],
            )
            guard let container = mediaContainer(root) else { continue }
            var metadata = dictionaries(container["Metadata"])
            for hub in dictionaries(container["Hub"]) {
                metadata.append(contentsOf: dictionaries(hub["Metadata"]))
            }
            result.append(contentsOf: metadata.flatMap {
                parsePrograms($0, provider: provider.identifier, dvrID: dvrID)
            })
        }
        lastPrograms = uniquePrograms(result).sorted { $0.startDate < $1.startDate }
        return lastPrograms
    }

    func onNow() async throws -> [LiveTVOnNowSection] {
        let now = Date()
        let programs = try await programs(from: now.addingTimeInterval(-4 * 3600), to: now.addingTimeInterval(4 * 3600))
            .filter(\.isCurrentlyAiring)
        return programs.isEmpty ? [] : [LiveTVOnNowSection(
            id: "now",
            title: String(localized: "livetv.onNow"),
            programs: programs,
        )]
    }

    func setFavorite(_ favorite: Bool, channel: LiveTVChannel) async throws {
        var keys = try await favoriteChannelKeys()
        let key = favoriteKey(for: channel)
        if favorite {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        let allChannels = try await channels()
        try await writeFavorites(allChannels.filter { keys.contains(favoriteKey(for: $0)) })
    }

    func reorderFavorites(_ channels: [LiveTVChannel]) async throws {
        try await writeFavorites(channels)
    }

    func startPlayback(channel: LiveTVChannel) async throws -> any LiveTVPlaybackSession {
        guard let dvrID = channel.dvrID else {
            throw PlexAPIError.invalidResponse
        }
        do {
            return try await PlexLiveTVPlaybackSession.start(channel: channel, dvrID: dvrID, context: context)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { throw error }
            return try await PlexLiveTVPlaybackSession.start(channel: channel, dvrID: dvrID, context: context)
        }
    }

    // MARK: DVR

    func upcomingRecordings() async throws -> [DVRRecording] {
        let root = try await network.json(path: "/media/subscriptions/scheduled")
        guard let container = mediaContainer(root) else { return [] }
        return dictionaries(container["MediaGrabOperation"]).map { operation in
            let metadata = dictionary(operation["Metadata"]) ?? [:]
            let program = parsePrograms(metadata, provider: "").first
            let rawStatus = string(operation["status"])?.lowercased()
            return DVRRecording(
                id: string(operation["key"] ?? operation["id"]) ?? UUID().uuidString,
                title: program?.title ?? string(metadata["title"]) ?? String(localized: "livetv.program.unknown"),
                channelTitle: program.flatMap { program in lastPrograms.first(where: { $0.id == program.id })?.title },
                startDate: program?.startDate,
                endDate: program?.endDate,
                status: Self.recordingStatus(from: rawStatus) ?? .scheduled,
                programID: program?.id,
                playableMedia: nil,
                errorMessage: string(operation["error"]),
            )
        }
    }

    func recordingRules() async throws -> [DVRRecordingRule] {
        let root = try await network.json(
            path: "/media/subscriptions",
            queryItems: [
                URLQueryItem(name: "includeGrabs", value: "1"),
                URLQueryItem(name: "includeStorage", value: "1"),
            ],
        )
        guard let container = mediaContainer(root) else { return [] }
        return dictionaries(container["MediaSubscription"]).compactMap(parseRule)
    }

    func completedRecordings() async throws -> [DVRRecording] {
        []
    }

    func recordingTemplate(for program: LiveTVProgram) async throws -> DVRRecordingTemplate {
        guard let guid = program.providerGUID else { throw PlexAPIError.invalidResponse }
        let root = try await network.json(
            path: "/media/subscriptions/template",
            queryItems: [URLQueryItem(name: "guid", value: guid)],
        )
        let container = mediaContainer(root) ?? [:]
        let templates = dictionaries(container["SubscriptionTemplate"])
        let subscriptions = templates.flatMap { dictionaries($0["MediaSubscription"]) }
        let selected = subscriptions.first(where: { bool($0["selected"]) == true }) ?? subscriptions.first
        let singleSubscription = subscriptions.first(where: { int($0["type"]) == 4 })
            ?? (subscriptions.count == 1 && int(subscriptions[0]["type"]) == nil ? subscriptions[0] : nil)
        let seriesSubscription = subscriptions.first(where: { int($0["type"]) == 2 })
        let libraries = try await PlexMediaServiceAdapter(
            context: context,
            sessionManager: nil,
            server: context.serverAccessSnapshot().serverIdentity,
        ).libraries()
            .filter { $0.type == .movie || $0.type == .series }
        return DVRRecordingTemplate(
            programID: program.id,
            single: singleSubscription.map { subscription in
                DVRRecordingModeTemplate(
                    options: recordingOptions(from: dictionaries(subscription["Setting"])),
                    defaultLibraryID: string(subscription["targetLibrarySectionID"]),
                )
            },
            series: seriesSubscription.map { subscription in
                DVRRecordingModeTemplate(
                    options: recordingOptions(from: dictionaries(subscription["Setting"])),
                    defaultLibraryID: string(subscription["targetLibrarySectionID"]),
                )
            },
            preferredMode: selected.flatMap { subscription in
                switch int(subscription["type"]) {
                case 2: .series
                case 4: .single
                default: nil
                }
            } ?? (singleSubscription != nil ? .single : seriesSubscription != nil ? .series : nil),
            libraries: libraries,
        )
    }

    private func recordingOptions(from settings: [[String: Any]]) -> [DVRRecordingOption] {
        settings
            .filter { bool($0["hidden"]) != true && bool($0["advanced"]) != true }
            .compactMap { setting -> DVRRecordingOption? in
                guard let id = string(setting["id"]) else { return nil }
                let title = string(setting["label"]) ?? id
                let enumValues = string(setting["enumValues"])
                let kind: DVRRecordingOptionKind = if let enumValues, !enumValues.isEmpty {
                    .choice(enumValues.split(separator: "|").map { value in
                        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
                        return DVRRecordingOptionChoice(id: parts[0], title: parts.count > 1 ? parts[1] : parts[0])
                    })
                } else if string(setting["type"])?.lowercased() == "bool" {
                    .toggle
                } else if string(setting["type"])?.lowercased().contains("int") == true {
                    .integer
                } else {
                    .text
                }
                return DVRRecordingOption(
                    id: id,
                    title: title,
                    summary: string(setting["summary"]),
                    kind: kind,
                    defaultValue: string(setting["value"] ?? setting["default"]) ?? "",
                    currentValue: string(setting["value"]),
                )
            }
    }

    func schedule(_ request: DVRRecordingRequest) async throws {
        guard let guid = request.program.providerGUID else { throw PlexAPIError.invalidResponse }
        let root = try await network.json(
            path: "/media/subscriptions/template",
            queryItems: [URLQueryItem(name: "guid", value: guid)],
        )
        let container = mediaContainer(root) ?? [:]
        let entries = dictionaries(container["SubscriptionTemplate"]).flatMap { dictionaries($0["MediaSubscription"]) }
        let desiredType = request.recordsSeries ? 2 : 4
        let entry = entries.first(where: { int($0["type"]) == desiredType }) ?? entries.first
        guard let entry else { throw PlexAPIError.invalidResponse }
        var query: [URLQueryItem] = []
        if let parameters = string(entry["parameters"]),
           let components = URLComponents(string: "https://localhost/?\(parameters)")
        {
            query.append(contentsOf: components.queryItems ?? [])
        }
        if let library = request.targetLibraryID {
            query.append(URLQueryItem(
                name: "targetLibrarySectionID",
                value: library,
            ))
        }
        query.append(URLQueryItem(name: "type", value: String(desiredType)))
        query.append(contentsOf: request.options.map { URLQueryItem(name: "prefs[\($0.key)]", value: $0.value) })
        _ = try await network.json(path: "/media/subscriptions", queryItems: query, method: "POST")
    }

    func update(rule: DVRRecordingRule, options: [String: String]) async throws {
        try await network.send(
            path: "/media/subscriptions/\(rule.id)",
            queryItems: options.map { URLQueryItem(name: "prefs[\($0.key)]", value: $0.value) },
            method: "PUT",
        )
    }

    func cancel(recordingID: String) async throws {
        let path = recordingID.hasPrefix("/") ? recordingID : "/media/grabbers/operations/\(recordingID)"
        try await network.send(path: path, method: "DELETE")
    }

    func delete(ruleID: String) async throws {
        try await network.send(path: "/media/subscriptions/\(ruleID)", method: "DELETE")
    }

    func deleteCompleted(recordingID _: String) async throws {
        throw PlexAPIError.invalidResponse
    }

    func reloadGuide() async throws {
        for dvr in dvrs {
            guard let id = string(dvr["key"]) else { continue }
            try await network.send(path: "/livetv/dvrs/\(id)/reloadGuide", method: "POST")
        }
    }

    // MARK: Parsing

    private func discover() async throws {
        let dvrRoot = try await network.json(path: "/livetv/dvrs")
        dvrs = mediaContainer(dvrRoot).map { dictionaries($0["Dvr"]) } ?? []
        guard !dvrs.isEmpty else { providers = []; return }
        let providerRoot = try await network.json(path: "/media/providers")
        let container = mediaContainer(providerRoot) ?? [:]
        providers = dictionaries(container["MediaProvider"]).flatMap { provider -> [EPGProvider] in
            guard let identifier = string(provider["identifier"]), identifier.contains("epg") else { return [] }
            let id = string(provider["id"])
            return dictionaries(provider["Feature"]).compactMap { feature in
                guard string(feature["type"])?.lowercased().contains("grid") == true,
                      let key = string(feature["key"])
                else { return nil }
                return EPGProvider(id: id, identifier: identifier, gridPath: key)
            }
        }
        if providers.isEmpty {
            providers = dvrs.compactMap { dvr in
                guard let lineup = string(dvr["lineup"]) else { return nil }
                return EPGProvider(id: nil, identifier: lineup, gridPath: "/\(lineup)/grid")
            }
        }
    }

    private func ensureDiscovered() async throws {
        if dvrs.isEmpty || providers.isEmpty {
            try await discover()
        }
    }

    private func enabledChannelIDs(for dvrID: String?) -> Set<String>? {
        let mappings = dvrs.first(where: { string($0["key"]) == dvrID })
            .map { dictionaries($0["ChannelMapping"]) } ?? []
        guard !mappings.isEmpty else { return nil }
        return Set(mappings.compactMap { bool($0["enabled"]) == true ? string($0["channelKey"]) : nil })
    }

    private func matchingDVRID(provider: EPGProvider) -> String? {
        let matches = dvrs
            .filter { string($0["lineup"]) == provider.identifier }
            .compactMap { string($0["key"]) }
        if matches.count == 1 {
            return matches[0]
        }
        guard matches.isEmpty, dvrs.count == 1 else { return nil }
        return dvrs.first.flatMap { string($0["key"]) }
    }

    private func parsePrograms(_ metadata: [String: Any], provider: String, dvrID: String? = nil) -> [LiveTVProgram] {
        let media = dictionaries(metadata["Media"])
        let airings = media.isEmpty ? [metadata] : media
        return airings.compactMap { airing in
            guard let start = double(airing["beginsAt"] ?? metadata["beginsAt"]),
                  let end = double(airing["endsAt"] ?? metadata["endsAt"]),
                  end > start
            else { return nil }
            let channel = string(airing["channelIdentifier"] ?? metadata["channelIdentifier"])
                ?? dictionaries(metadata["Channel"]).first.flatMap { string($0["id"]) }
            guard let channel else { return nil }
            let ratingKey = string(metadata["ratingKey"] ?? metadata["key"]) ?? "\(channel)-\(Int(start))"
            let channelIdentity = LiveTVChannelIdentity(
                providerID: channel,
                lineupID: provider.isEmpty ? nil : provider,
                dvrID: dvrID,
            )
            return LiveTVProgram(
                id: "\(ratingKey)-\(Int(start))",
                channelID: channel,
                channelIdentity: channelIdentity,
                title: string(metadata["title"]) ?? String(localized: "livetv.program.unknown"),
                seriesTitle: string(metadata["grandparentTitle"]),
                summary: string(metadata["summary"]),
                startDate: Date(timeIntervalSince1970: start),
                endDate: Date(timeIntervalSince1970: end),
                thumbPath: string(metadata["thumb"] ?? metadata["grandparentThumb"]),
                artPath: string(metadata["art"]),
                seasonNumber: int(metadata["parentIndex"]),
                episodeNumber: int(metadata["index"]),
                isLive: bool(metadata["live"]) ?? false,
                isPremiere: bool(metadata["premiere"]) ?? false,
                recordingID: string(metadata["subscriptionID"]),
                seriesRecordingID: string(metadata["grandparentSubscriptionID"]),
                recordingStatus: Self.recordingStatus(from: string(metadata["status"])),
                providerGUID: string(metadata["guid"]) ?? "plex://\(provider)/\(ratingKey)",
            )
        }
    }

    private static func recordingStatus(from rawValue: String?) -> DVRRecordingStatus? {
        switch rawValue?.lowercased() {
        case "scheduled", "new": .scheduled
        case "grabbing", "inprogress", "recording": .recording
        case "completed", "complete": .completed
        case "cancelled", "canceled": .cancelled
        case "error": .error
        default: nil
        }
    }

    private func parseRule(_ item: [String: Any]) -> DVRRecordingRule? {
        guard let id = string(item["key"] ?? item["id"]) else { return nil }
        let settings = dictionaries(item["Setting"])
        return DVRRecordingRule(
            id: id,
            title: string(item["title"]) ?? String(localized: "livetv.recording.rule"),
            isSeries: int(item["type"]) == 2,
            targetLibraryID: string(item["targetLibrarySectionID"]),
            targetLibraryTitle: string(item["librarySectionTitle"]),
            optionValues: Dictionary(uniqueKeysWithValues: settings.compactMap { setting in
                guard let id = string(setting["id"]), let value = string(setting["value"]) else { return nil }
                return (id, value)
            }),
            options: recordingOptions(from: settings),
        )
    }

    private func favoriteChannelKeys() async throws -> Set<FavoriteChannelKey> {
        let snapshot = try context.serverAccessSnapshot()
        var request = URLRequest(url: URL(string: "https://epg.provider.plex.tv/settings/favoriteChannels")!)
        request.setValue(context.authTokenCloud ?? snapshot.authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(snapshot.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("5.1", forHTTPHeaderField: "X-Plex-Provider-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200 ..< 300 ~= response.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        let root = object as? [String: Any] ?? [:]
        let entries = dictionaries(root["MediaContainer"]).flatMap { dictionaries($0["FavoriteChannel"]) }
            + dictionaries(root["FavoriteChannel"])
        return Set(entries.compactMap { entry in
            guard let providerID = string(entry["id"] ?? entry["key"]),
                  let source = string(entry["source"])
            else { return nil }
            return FavoriteChannelKey(source: source, providerID: providerID)
        })
    }

    private func favoriteKey(for channel: LiveTVChannel) -> FavoriteChannelKey {
        FavoriteChannelKey(
            source: "server://\(context.serverIdentifier ?? "")/\(channel.lineupID ?? "")",
            providerID: channel.providerID,
        )
    }

    private func writeFavorites(_ channels: [LiveTVChannel]) async throws {
        let snapshot = try context.serverAccessSnapshot()
        var request = URLRequest(url: URL(string: "https://epg.provider.plex.tv/settings/favoriteChannels")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(context.authTokenCloud ?? snapshot.authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(snapshot.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("5.1", forHTTPHeaderField: "X-Plex-Provider-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "FavoriteChannel": channels.map { [
                "source": "server://\(snapshot.serverIdentifier)/\($0.lineupID ?? "")",
                "id": $0.providerID,
                "title": $0.title,
                "vcn": $0.number ?? "",
            ] },
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200 ..< 300 ~= response.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}

@MainActor
private final class PlexLiveTVPlaybackSession: LiveTVPlaybackSession {
    let channel: LiveTVChannel
    let backgroundPolicy = LiveTVBackgroundPolicy.retainSession
    private(set) var captureRange: LiveTVCaptureRange?
    private let context: PlexAPIContext
    private let network: PlexServerNetworkClient
    private let dvrID: String
    private let sessionPath: String
    private let sessionIdentifier: String
    private let transcodeIdentifier: String
    private let ratingKey: String
    private let program: LiveTVProgram?
    private let burnsBitmapSubtitles: Bool

    private init(
        channel: LiveTVChannel,
        dvrID: String,
        context: PlexAPIContext,
        sessionPath: String,
        sessionIdentifier: String,
        ratingKey: String,
        program: LiveTVProgram?,
        burnsBitmapSubtitles: Bool,
        captureRange: LiveTVCaptureRange?,
    ) {
        self.channel = channel
        self.dvrID = dvrID
        self.context = context
        network = PlexServerNetworkClient(context: context)
        self.sessionPath = sessionPath
        self.sessionIdentifier = sessionIdentifier
        transcodeIdentifier = UUID().uuidString
        self.ratingKey = ratingKey
        self.program = program
        self.burnsBitmapSubtitles = burnsBitmapSubtitles
        self.captureRange = captureRange
    }

    static func start(
        channel: LiveTVChannel,
        dvrID: String,
        context: PlexAPIContext,
    ) async throws -> PlexLiveTVPlaybackSession {
        let sessionIdentifier = UUID().uuidString
        let network = PlexServerNetworkClient(context: context)
        let root = try await network.json(
            path: "/livetv/dvrs/\(dvrID)/channels/\(channel.providerID)/tune",
            queryItems: [URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionIdentifier)],
            method: "POST",
        )
        guard let container = mediaContainer(root) else { throw PlexAPIError.invalidResponse }
        var metadata = dictionary(container["Metadata"])
        if metadata == nil {
            let subscriptions = dictionaries(container["MediaSubscription"])
            let operations = subscriptions.flatMap { dictionaries($0["MediaGrabOperation"]) }
            metadata = operations.compactMap { dictionary($0["Metadata"]) }.first
        }
        guard let metadata, let path = string(metadata["key"]) else {
            throw PlexAPIError.invalidResponse
        }
        let ratingKey = string(metadata["ratingKey"]) ?? channel.providerID
        let streams = dictionaries(metadata["Media"]).flatMap { media in
            dictionaries(media["Part"]).flatMap { dictionaries($0["Stream"]) }
        } + dictionaries(metadata["Stream"])
        let burnsBitmapSubtitles = streams.contains { stream in
            guard int(stream["streamType"]) == 3, bool(stream["selected"]) == true else { return false }
            let codec = string(stream["codec"])?.lowercased() ?? ""
            return ["pgs", "dvb_subtitle", "dvd_subtitle", "vobsub"].contains(codec)
        }
        let transcode = dictionary(container["TranscodeSession"]) ?? dictionaries(container["TranscodeSession"]).first
        let capture = plexCaptureRange(from: transcode)
        return PlexLiveTVPlaybackSession(
            channel: channel,
            dvrID: dvrID,
            context: context,
            sessionPath: path,
            sessionIdentifier: sessionIdentifier,
            ratingKey: ratingKey,
            program: nil,
            burnsBitmapSubtitles: burnsBitmapSubtitles,
            captureRange: capture,
        )
    }

    func source(offsetFromCaptureStart: TimeInterval?) async throws -> LiveTVPlaybackSource {
        let snapshot = try context.serverAccessSnapshot()
        var query: [URLQueryItem] = [
            .init(name: "hasMDE", value: "1"), .init(name: "path", value: sessionPath),
            .init(name: "mediaIndex", value: "0"), .init(name: "partIndex", value: "0"),
            .init(name: "protocol", value: "hls"), .init(name: "fastSeek", value: "1"),
            .init(name: "directPlay", value: "0"), .init(name: "directStream", value: "1"),
            .init(name: "directStreamAudio", value: "1"),
            .init(name: "subtitles", value: burnsBitmapSubtitles ? "burn" : "none"),
            .init(name: "session", value: transcodeIdentifier),
            .init(name: "X-Plex-Session-Identifier", value: sessionIdentifier),
            .init(name: "X-Plex-Client-Identifier", value: snapshot.clientIdentifier),
            .init(name: "X-Plex-Token", value: snapshot.authToken),
            .init(name: "X-Plex-Incomplete-Segments", value: "1"),
        ]
        if let offsetFromCaptureStart {
            query.append(.init(name: "offset", value: String(Int(offsetFromCaptureStart))))
        }
        var components = URLComponents(
            url: snapshot.baseURL.appendingPathComponent("/video/:/transcode/universal/start.m3u8"),
            resolvingAgainstBaseURL: false,
        )!
        components.queryItems = query
        guard let url = components.url else { throw PlexAPIError.invalidURL }
        return LiveTVPlaybackSource(
            url: url,
            httpHeaders: [:],
            program: program,
            captureRange: captureRange,
            nativeRemoteHLS: true,
        )
    }

    func report(position: TimeInterval, isPaused: Bool) async throws -> LiveTVCaptureRange? {
        let root = try await network.json(path: "/:/timeline", queryItems: [
            .init(name: "ratingKey", value: ratingKey), .init(name: "key", value: sessionPath),
            .init(name: "state", value: isPaused ? "paused" : "playing"),
            .init(name: "time", value: String(Int(position * 1000))),
            .init(name: "duration", value: String(max(Int(position * 1000), 1))),
            .init(name: "playbackTime", value: String(Int(position * 1000))),
            .init(name: "X-Plex-Session-Identifier", value: sessionIdentifier),
        ])
        let container = mediaContainer(root)
        let transcode = container
            .flatMap { dictionary($0["TranscodeSession"]) ?? dictionaries($0["TranscodeSession"]).first }
        if let range = plexCaptureRange(from: transcode) {
            captureRange = range
        }
        return captureRange
    }

    func recover() async throws -> any LiveTVPlaybackSession {
        try await Self.start(channel: channel, dvrID: dvrID, context: context)
    }

    func stop() async {
        do {
            _ = try await report(position: 0, isPaused: true)
        } catch {
            LiveTVErrorReporting.capture(error)
        }
        do {
            try await PlaybackRepository(context: context).stopTranscode(sessionIdentifier: transcodeIdentifier)
        } catch {
            LiveTVErrorReporting.capture(error)
        }
    }
}

private extension PlexAPIContext.ServerAccessSnapshot {
    var serverIdentity: ServerIdentity {
        ServerIdentity(provider: .plex, id: serverIdentifier)
    }
}

private func mediaContainer(_ root: [String: Any]) -> [String: Any]? {
    dictionary(root["MediaContainer"]) ?? root
}

private func dictionary(_ value: Any?) -> [String: Any]? {
    if let value = value as? [String: Any] {
        return value
    }
    return (value as? [[String: Any]])?.first
}

private func dictionaries(_ value: Any?) -> [[String: Any]] {
    if let values = value as? [[String: Any]] {
        return values
    }
    if let value = value as? [String: Any] {
        return [value]
    }
    return []
}

private func string(_ value: Any?) -> String? {
    switch value {
    case let value as String: value
    case let value as NSNumber: value.stringValue
    default: nil
    }
}

private func double(_ value: Any?) -> Double? {
    switch value {
    case let value as Double: value
    case let value as NSNumber: value.doubleValue
    case let value as String: Double(value)
    default: nil
    }
}

private func int(_ value: Any?) -> Int? {
    double(value).map(Int.init)
}

private func bool(_ value: Any?) -> Bool? {
    switch value {
    case let value as Bool: value
    case let value as NSNumber: value.boolValue
    case let value as String: ["1", "true", "yes"].contains(value.lowercased())
    default: nil
    }
}

private func plexCaptureRange(from value: [String: Any]?) -> LiveTVCaptureRange? {
    guard let value,
          let timestamp = double(value["timeStamp"]),
          let minimum = double(value["minOffsetAvailable"]),
          let maximum = double(value["maxOffsetAvailable"])
    else { return nil }
    return LiveTVCaptureRange(
        startDate: Date(timeIntervalSince1970: timestamp + minimum),
        endDate: Date(timeIntervalSince1970: timestamp + maximum),
    )
}

private func unique(_ channels: [LiveTVChannel]) -> [LiveTVChannel] {
    var identities: Set<LiveTVChannelIdentity> = []
    return channels.filter { identities.insert($0.identity).inserted }
}

private func uniquePrograms(_ programs: [LiveTVProgram]) -> [LiveTVProgram] {
    var identities: Set<LiveTVProgramIdentity> = []
    return programs.filter { identities.insert($0.identity).inserted }
}

private func channelSort(_ lhs: LiveTVChannel, _ rhs: LiveTVChannel) -> Bool {
    if let left = lhs.number.flatMap(Double.init), let right = rhs.number.flatMap(Double.init),
       left != right
    {
        return left < right
    }
    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
}
