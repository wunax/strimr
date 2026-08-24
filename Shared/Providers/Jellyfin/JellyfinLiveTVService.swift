import Foundation

@MainActor
final class JellyfinLiveTVService: MediaLiveTVService, MediaDVRService {
    private let context: JellyfinAPIContext
    private let server: ServerIdentity
    private let catalog: JellyfinCatalogService
    private var lastChannels: [LiveTVChannel] = []

    init(context: JellyfinAPIContext, server: ServerIdentity) {
        self.context = context
        self.server = server
        catalog = JellyfinCatalogService(context: context)
    }

    var dvr: (any MediaDVRService)? { self }
    var supportsServerCaptureBuffer: Bool { false }
    var supportsCompletedRecordings: Bool { true }
    var canManageRecordings: Bool {
        context.currentUser?.policy?.isAdministrator == true
            || context.currentUser?.policy?.enableLiveTVManagement == true
    }
    var canDeleteRecordings: Bool {
        context.currentUser?.policy?.isAdministrator == true
            || context.currentUser?.policy?.enableContentDeletion == true
    }

    func isAvailable() async throws -> Bool {
        guard context.currentUser?.policy?.enableLiveTVAccess != false else { return false }
        let response: JellyfinQueryResult<JellyfinLiveChannelDTO> = try await context.get(
            path: ["LiveTv", "Channels"],
            query: userQuery() + [URLQueryItem(name: "Limit", value: "1")],
        )
        return response.totalRecordCount.map { $0 > 0 } ?? !response.items.isEmpty
    }

    func channels() async throws -> [LiveTVChannel] {
        let response: JellyfinQueryResult<JellyfinLiveChannelDTO> = try await context.get(
            path: ["LiveTv", "Channels"],
            query: userQuery() + [
                URLQueryItem(name: "EnableImages", value: "true"),
                URLQueryItem(name: "EnableUserData", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ],
        )
        let storedOrder = favoriteOrder()
        let order = Dictionary(uniqueKeysWithValues: storedOrder.enumerated().map { ($1, $0) })
        lastChannels = response.items.map { item in
            LiveTVChannel(
                id: item.id,
                title: item.name,
                callSign: item.callSign,
                number: item.number,
                thumbPath: JellyfinArtworkPath.make(ownerID: item.id, type: "Primary", tag: item.imageTags?["Primary"]),
                artPath: nil,
                lineupID: nil,
                dvrID: nil,
                isHD: item.isHD ?? false,
                isFavorite: item.userData?.isFavorite ?? storedOrder.contains(item.id),
            )
        }.sorted { lhs, rhs in
            switch (order[lhs.id], order[rhs.id]) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
        }
        return lastChannels
    }

    func programs(from: Date, to: Date) async throws -> [LiveTVProgram] {
        let response: JellyfinQueryResult<JellyfinLiveProgramDTO> = try await context.get(
            path: ["LiveTv", "Programs"],
            query: userQuery() + [
                URLQueryItem(name: "MinEndDate", value: Self.iso.string(from: from)),
                URLQueryItem(name: "MaxStartDate", value: Self.iso.string(from: to)),
                URLQueryItem(name: "EnableImages", value: "true"),
                URLQueryItem(name: "EnableUserData", value: "true"),
                URLQueryItem(name: "SortBy", value: "StartDate"),
                URLQueryItem(name: "SortOrder", value: "Ascending"),
            ],
        )
        return response.items.compactMap(mapProgram)
    }

    func onNow() async throws -> [LiveTVOnNowSection] {
        async let now = fetchProgramHub(
            path: ["LiveTv", "Programs", "Recommended"],
            query: userQuery() + [
                URLQueryItem(name: "IsAiring", value: "true"),
                URLQueryItem(name: "Limit", value: "9"),
                URLQueryItem(name: "ImageTypeLimit", value: "1"),
                URLQueryItem(name: "EnableImageTypes", value: "Primary,Thumb,Backdrop"),
                URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
                URLQueryItem(name: "Fields", value: "ChannelInfo,PrimaryImageAspectRatio"),
            ],
        )
        async let series = fetchProgramHub(
            path: ["LiveTv", "Programs"],
            query: upcomingHubQuery(
                filters: [
                    URLQueryItem(name: "IsMovie", value: "false"),
                    URLQueryItem(name: "IsSports", value: "false"),
                    URLQueryItem(name: "IsKids", value: "false"),
                    URLQueryItem(name: "IsNews", value: "false"),
                    URLQueryItem(name: "IsSeries", value: "true"),
                ],
                fields: "ChannelInfo,PrimaryImageAspectRatio",
            ),
        )
        async let movies = fetchProgramHub(
            path: ["LiveTv", "Programs"],
            query: upcomingHubQuery(
                filters: [URLQueryItem(name: "IsMovie", value: "true")],
                fields: "ChannelInfo",
            ),
        )
        async let sports = fetchProgramHub(
            path: ["LiveTv", "Programs"],
            query: upcomingHubQuery(
                filters: [URLQueryItem(name: "IsSports", value: "true")],
                fields: "ChannelInfo,PrimaryImageAspectRatio",
            ),
        )
        async let kids = fetchProgramHub(
            path: ["LiveTv", "Programs"],
            query: upcomingHubQuery(
                filters: [URLQueryItem(name: "IsKids", value: "true")],
                fields: "ChannelInfo,PrimaryImageAspectRatio",
            ),
        )
        async let news = fetchProgramHub(
            path: ["LiveTv", "Programs"],
            query: upcomingHubQuery(
                filters: [URLQueryItem(name: "IsNews", value: "true")],
                fields: "ChannelInfo,PrimaryImageAspectRatio",
            ),
        )

        let values = try await (now, series, movies, sports, kids, news)
        let sections: [(id: String, title: String, programs: [LiveTVProgram])] = [
            ("now", String(localized: "livetv.onNow"), values.0),
            ("series", String(localized: "livetv.onNow.series"), values.1),
            ("movies", String(localized: "livetv.onNow.movies"), values.2),
            ("sports", String(localized: "livetv.onNow.sports"), values.3),
            ("kids", String(localized: "livetv.onNow.kids"), values.4),
            ("news", String(localized: "livetv.onNow.news"), values.5),
        ]
        return sections.compactMap { section in
            guard !section.programs.isEmpty else { return nil }
            return LiveTVOnNowSection(id: section.id, title: section.title, programs: section.programs)
        }
    }

    func setFavorite(_ favorite: Bool, channel: LiveTVChannel) async throws {
        try await catalog.setFavorite(favorite, itemID: channel.id)
        var order = favoriteOrder()
        order.removeAll { $0 == channel.id }
        if favorite { order.append(channel.id) }
        storeFavoriteOrder(order)
    }

    func reorderFavorites(_ channels: [LiveTVChannel]) async throws {
        storeFavoriteOrder(channels.map(\.id))
    }

    func startPlayback(channel: LiveTVChannel) async throws -> any LiveTVPlaybackSession {
        try await JellyfinLiveTVPlaybackSession.start(channel: channel, context: context)
    }

    // MARK: DVR

    func upcomingRecordings() async throws -> [DVRRecording] {
        let response: JellyfinQueryResult<JellyfinTimerDTO> = try await context.get(
            path: ["LiveTv", "Timers"],
        )
        return response.items
            .filter { timer in
                switch timer.status?.lowercased() {
                case "cancelled", "completed": false
                default: true
                }
            }
            .map(mapTimer)
    }

    func recordingRules() async throws -> [DVRRecordingRule] {
        let response: JellyfinQueryResult<JellyfinSeriesTimerDTO> = try await context.get(path: ["LiveTv", "SeriesTimers"])
        return response.items.compactMap { timer in
            guard let id = timer.id else { return nil }
            return DVRRecordingRule(
                id: id,
                title: timer.name ?? String(localized: "livetv.recording.rule"),
                isSeries: true,
                targetLibraryID: nil,
                targetLibraryTitle: nil,
                optionValues: timer.optionValues,
            )
        }
    }

    func completedRecordings() async throws -> [DVRRecording] {
        let response: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["LiveTv", "Recordings"],
            query: userQuery() + [
                URLQueryItem(name: "EnableImages", value: "true"),
                URLQueryItem(name: "EnableUserData", value: "true"),
                URLQueryItem(name: "IsInProgress", value: "false"),
            ],
        )
        return response.items.map { item in
            DVRRecording(
                id: item.id,
                title: item.name,
                channelTitle: nil,
                startDate: nil,
                endDate: nil,
                status: .completed,
                programID: item.id,
                playableMedia: MediaItem(jellyfinItem: item, server: server),
                errorMessage: nil,
            )
        }
    }

    func recordingTemplate(for program: LiveTVProgram) async throws -> DVRRecordingTemplate {
        async let timerTask = timerDefaults(for: program.id)
        async let detailsTask: JellyfinLiveProgramDTO = context.get(
            path: ["LiveTv", "Programs", program.id],
            query: userQuery(),
        )
        let (timer, details) = try await (timerTask, detailsTask)
        let supportsSeries = details.isSeries == true
            || details.seriesID?.isEmpty == false
            || details.seriesName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty == false
        let singleOptions = [
            DVRRecordingOption(id: "prePaddingSeconds", title: String(localized: "livetv.recording.prePadding"), summary: nil, kind: .integer, defaultValue: String(integer(timer["PrePaddingSeconds"]) ?? 0)),
            DVRRecordingOption(id: "postPaddingSeconds", title: String(localized: "livetv.recording.postPadding"), summary: nil, kind: .integer, defaultValue: String(integer(timer["PostPaddingSeconds"]) ?? 0)),
        ]
        let seriesOptions = [
            singleOptions[0],
            singleOptions[1],
            DVRRecordingOption(id: "recordNewOnly", title: String(localized: "livetv.recording.newOnly"), summary: nil, kind: .toggle, defaultValue: String(boolean(timer["RecordNewOnly"]) ?? false)),
            DVRRecordingOption(id: "recordAnyTime", title: String(localized: "livetv.recording.anyTime"), summary: nil, kind: .toggle, defaultValue: String(boolean(timer["RecordAnyTime"]) ?? true)),
            DVRRecordingOption(id: "recordAnyChannel", title: String(localized: "livetv.recording.anyChannel"), summary: nil, kind: .toggle, defaultValue: String(boolean(timer["RecordAnyChannel"]) ?? false)),
            DVRRecordingOption(id: "keepUpTo", title: String(localized: "livetv.recording.keepUpTo"), summary: nil, kind: .integer, defaultValue: String(integer(timer["KeepUpTo"]) ?? 0)),
            DVRRecordingOption(
                id: "keepUntil",
                title: String(localized: "livetv.recording.keepUntil"),
                summary: nil,
                kind: .choice(Self.keepUntilChoices()),
                defaultValue: string(timer["KeepUntil"]) ?? "UntilDeleted",
            ),
            DVRRecordingOption(id: "skipEpisodesInLibrary", title: String(localized: "livetv.recording.skipInLibrary"), summary: nil, kind: .toggle, defaultValue: String(boolean(timer["SkipEpisodesInLibrary"]) ?? false)),
        ]
        return DVRRecordingTemplate(
            programID: program.id,
            single: DVRRecordingModeTemplate(options: singleOptions, defaultLibraryID: nil),
            series: supportsSeries ? DVRRecordingModeTemplate(options: seriesOptions, defaultLibraryID: nil) : nil,
            preferredMode: .single,
            libraries: [],
        )
    }

    func schedule(_ request: DVRRecordingRequest) async throws {
        var timer = try await timerDefaults(for: request.program.id)
        timer["ProgramId"] = request.program.id
        timer["ChannelId"] = request.program.channelID
        applyOptions(request.options, to: &timer, includeSeriesOptions: request.recordsSeries)

        do {
            try await postTimer(timer, path: ["LiveTv", request.recordsSeries ? "SeriesTimers" : "Timers"])
        } catch JellyfinAPIError.httpStatus(400) where !request.recordsSeries {
            throw JellyfinAPIError.recordingConflict
        }
    }

    func update(rule: DVRRecordingRule, options: [String: String]) async throws {
        let data = try await context.rawData(path: ["LiveTv", "SeriesTimers", rule.id])
        var timer = try rawObject(data)
        applyOptions(options, to: &timer, includeSeriesOptions: true)
        try await postTimer(timer, path: ["LiveTv", "SeriesTimers", rule.id])
    }

    func cancel(recordingID: String) async throws {
        try await context.send(path: ["LiveTv", "Timers", recordingID], method: "DELETE")
    }

    func delete(ruleID: String) async throws {
        try await context.send(path: ["LiveTv", "SeriesTimers", ruleID], method: "DELETE")
    }

    func deleteCompleted(recordingID: String) async throws {
        guard canDeleteRecordings else { throw JellyfinAPIError.permissionDenied }
        try await context.send(path: ["LiveTv", "Recordings", recordingID], method: "DELETE")
    }

    func reloadGuide() async throws {
        // Jellyfin owns guide refresh as a scheduled server task; clients refresh their local window.
    }

    private func mapProgram(_ item: JellyfinLiveProgramDTO) -> LiveTVProgram? {
        guard let start = Self.date(item.startDate), let end = Self.date(item.endDate), let channelID = item.channelID else { return nil }
        return LiveTVProgram(
            id: item.id,
            channelID: channelID,
            title: item.name,
            seriesTitle: item.seriesName,
            summary: item.overview,
            startDate: start,
            endDate: end,
            thumbPath: JellyfinArtworkPath.make(ownerID: item.id, type: "Primary", tag: item.imageTags?["Primary"]),
            artPath: nil,
            seasonNumber: item.parentIndexNumber,
            episodeNumber: item.indexNumber,
            isLive: item.isLive ?? false,
            isPremiere: item.isPremiere ?? false,
            recordingID: item.timerID?.isEmpty == false ? item.timerID : nil,
            seriesRecordingID: item.timerID?.isEmpty == false ? item.seriesTimerID : nil,
            recordingStatus: item.timerID?.isEmpty == false ? Self.recordingStatus(from: item.status) : nil,
            providerGUID: nil,
        )
    }

    private func fetchProgramHub(path: [String], query: [URLQueryItem]) async throws -> [LiveTVProgram] {
        let response: JellyfinQueryResult<JellyfinLiveProgramDTO> = try await context.get(path: path, query: query)
        return response.items.compactMap(mapProgram)
    }

    private func upcomingHubQuery(filters: [URLQueryItem], fields: String) -> [URLQueryItem] {
        userQuery() + [
            URLQueryItem(name: "HasAired", value: "false"),
            URLQueryItem(name: "Limit", value: "9"),
            URLQueryItem(name: "EnableTotalRecordCount", value: "false"),
            URLQueryItem(name: "Fields", value: fields),
            URLQueryItem(name: "EnableImageTypes", value: "Primary,Thumb"),
        ] + filters
    }

    private func mapTimer(_ timer: JellyfinTimerDTO) -> DVRRecording {
        let status = Self.recordingStatus(from: timer.status) ?? .scheduled
        return DVRRecording(
            id: timer.id ?? UUID().uuidString,
            title: timer.name ?? String(localized: "livetv.program.unknown"),
            channelTitle: timer.channelName,
            startDate: Self.date(timer.startDate),
            endDate: Self.date(timer.endDate),
            status: status,
            programID: timer.programID,
            playableMedia: nil,
            errorMessage: nil,
        )
    }

    private static func recordingStatus(from rawValue: String?) -> DVRRecordingStatus? {
        switch rawValue?.lowercased() {
        case "new", "scheduled": .scheduled
        case "inprogress", "grabbing", "recording": .recording
        case "completed", "complete": .completed
        case "cancelled", "canceled": .cancelled
        case "error", "conflictednotok": .error
        case "conflictedok": .scheduled
        default: nil
        }
    }

    private func timerDefaults(for programID: String) async throws -> [String: Any] {
        let data = try await context.rawData(
            path: ["LiveTv", "Timers", "Defaults"],
            query: [URLQueryItem(name: "ProgramId", value: programID)],
        )
        return try rawObject(data)
    }

    private func rawObject(_ data: Data) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw JellyfinAPIError.invalidResponse
            }
            return object
        } catch let error as JellyfinAPIError {
            throw error
        } catch {
            throw JellyfinAPIError.invalidResponse
        }
    }

    private func postTimer(_ timer: [String: Any], path: [String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: timer)
        try await context.send(path: path, method: "POST", body: body)
    }

    private func applyOptions(
        _ options: [String: String],
        to timer: inout [String: Any],
        includeSeriesOptions: Bool,
    ) {
        if let value = Int(options["prePaddingSeconds"] ?? "") {
            timer["PrePaddingSeconds"] = value
        }
        if let value = Int(options["postPaddingSeconds"] ?? "") {
            timer["PostPaddingSeconds"] = value
        }
        guard includeSeriesOptions else { return }
        if let value = parseBool(options["recordNewOnly"]) {
            timer["RecordNewOnly"] = value
        }
        if let value = parseBool(options["recordAnyTime"]) {
            timer["RecordAnyTime"] = value
        }
        if let value = parseBool(options["recordAnyChannel"]) {
            timer["RecordAnyChannel"] = value
        }
        if let value = Int(options["keepUpTo"] ?? "") {
            timer["KeepUpTo"] = value
        }
        if let value = options["keepUntil"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            timer["KeepUntil"] = value
        }
        if let value = parseBool(options["skipEpisodesInLibrary"]) {
            timer["SkipEpisodesInLibrary"] = value
        }
    }

    private static func keepUntilChoices() -> [DVRRecordingOptionChoice] {
        [
            .init(id: "UntilDeleted", title: String(localized: "livetv.recording.keepUntil.deleted")),
            .init(id: "UntilSpaceNeeded", title: String(localized: "livetv.recording.keepUntil.spaceNeeded")),
            .init(id: "UntilWatched", title: String(localized: "livetv.recording.keepUntil.watched")),
            .init(id: "UntilDate", title: String(localized: "livetv.recording.keepUntil.date")),
        ]
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return parseBool(value) }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func userQuery() -> [URLQueryItem] { [URLQueryItem(name: "UserId", value: context.connection?.userID)] }
    private var favoritesKey: String { "strimr.jellyfin.liveTV.favorites.\(server.id).\(context.connection?.userID ?? "")" }
    private func favoriteOrder() -> [String] { UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [] }
    private func storeFavoriteOrder(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: favoritesKey) }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return iso.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

@MainActor
private final class JellyfinLiveTVPlaybackSession: LiveTVPlaybackSession {
    let channel: LiveTVChannel
    let backgroundPolicy = LiveTVBackgroundPolicy.stopAndExit
    let captureRange: LiveTVCaptureRange? = nil
    private let context: JellyfinAPIContext
    private let url: URL
    private let headers: [String: String]
    private let playSessionID: String
    private let mediaSourceID: String
    private let liveStreamID: String?
    private let playMethod: String
    private var didReportStarted = false

    private init(channel: LiveTVChannel, context: JellyfinAPIContext, url: URL, headers: [String: String], playSessionID: String, mediaSourceID: String, liveStreamID: String?, playMethod: String) {
        self.channel = channel
        self.context = context
        self.url = url
        self.headers = headers
        self.playSessionID = playSessionID
        self.mediaSourceID = mediaSourceID
        self.liveStreamID = liveStreamID
        self.playMethod = playMethod
    }

    static func start(channel: LiveTVChannel, context: JellyfinAPIContext) async throws -> JellyfinLiveTVPlaybackSession {
        guard let userID = context.connection?.userID else { throw JellyfinAPIError.authenticationRequired }
        let request = JellyfinLivePlaybackInfoRequest(userID: userID)
        let info: JellyfinPlaybackInfo = try await context.post(
            path: ["Items", channel.id, "PlaybackInfo"],
            query: [URLQueryItem(name: "UserId", value: userID)],
            body: request,
        )
        guard let playSessionID = info.playSessionID,
              let source = info.mediaSources?.first
        else {
            throw JellyfinAPIError.noPlayableSource
        }

        let url: URL
        let headers: [String: String]
        let playMethod: String
        if let rawURL = source.transcodingURL,
           let transcodeURL = URL(string: rawURL, relativeTo: context.connection?.baseURL)?.absoluteURL
        {
            url = transcodeURL
            headers = try context.playbackHeaders()
            playMethod = "Transcode"
        } else if let rawPath = source.path,
                  let directURL = URL(string: rawPath),
                  let scheme = directURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  source.container?.lowercased() == "hls" || directURL.pathExtension.lowercased() == "m3u8"
        {
            url = directURL
            // This URL may point at a third-party origin. Never forward the
            // Jellyfin authorization header outside the Jellyfin server.
            headers = source.requiredHTTPHeaders ?? [:]
            playMethod = "DirectPlay"
        } else {
            throw JellyfinAPIError.noPlayableSource
        }
        return JellyfinLiveTVPlaybackSession(
            channel: channel,
            context: context,
            url: url,
            headers: headers,
            playSessionID: playSessionID,
            mediaSourceID: source.id,
            liveStreamID: source.liveStreamID,
            playMethod: playMethod,
        )
    }

    func source(offsetFromCaptureStart _: TimeInterval?) async throws -> LiveTVPlaybackSource {
        LiveTVPlaybackSource(url: url, httpHeaders: headers, program: nil, captureRange: nil, nativeRemoteHLS: true)
    }

    func report(position: TimeInterval, isPaused: Bool) async throws -> LiveTVCaptureRange? {
        let report = JellyfinLivePlaybackReport(
            itemID: channel.id,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID,
            positionTicks: JellyfinTime.ticks(fromSeconds: position),
            isPaused: isPaused,
            playMethod: playMethod,
        )
        let path = didReportStarted ? ["Sessions", "Playing", "Progress"] : ["Sessions", "Playing"]
        try await context.send(path: path, method: "POST", body: JSONEncoder().encode(report))
        didReportStarted = true
        return nil
    }

    func recover() async throws -> any LiveTVPlaybackSession { try await Self.start(channel: channel, context: context) }

    func stop() async {
        let report = JellyfinLivePlaybackReport(itemID: channel.id, mediaSourceID: mediaSourceID, playSessionID: playSessionID, positionTicks: 0, isPaused: true, playMethod: playMethod)
        do {
            try await context.send(path: ["Sessions", "Playing", "Stopped"], method: "POST", body: JSONEncoder().encode(report))
        } catch {
            LiveTVErrorReporting.capture(error)
        }
        if let liveStreamID {
            do {
                try await context.send(path: ["LiveStreams", "Close"], method: "POST", query: [URLQueryItem(name: "LiveStreamId", value: liveStreamID)])
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
        if playMethod == "Transcode" {
            do {
                try await context.stopEncoding(playSessionID: playSessionID)
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
    }
}

private struct JellyfinLivePlaybackInfoRequest: Encodable {
    let userID: String
    let startTimeTicks = 0
    let isPlayback = true
    let autoOpenLiveStream = true
    let enableDirectPlay = true
    let enableDirectStream = true
    let enableTranscoding = true
    let allowVideoStreamCopy = true
    let allowAudioStreamCopy = true
    let maxStreamingBitrate = 120_000_000
    let alwaysBurnInSubtitleWhenTranscoding = false
    let deviceProfile = JellyfinDeviceProfile.liveTV()

    private enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case startTimeTicks = "StartTimeTicks"
        case isPlayback = "IsPlayback"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case allowVideoStreamCopy = "AllowVideoStreamCopy"
        case allowAudioStreamCopy = "AllowAudioStreamCopy"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case alwaysBurnInSubtitleWhenTranscoding = "AlwaysBurnInSubtitleWhenTranscoding"
        case deviceProfile = "DeviceProfile"
    }
}

nonisolated private struct JellyfinLivePlaybackReport: Encodable {
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    let positionTicks: Int64
    let isPaused: Bool
    let playMethod: String

    private enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playMethod = "PlayMethod"
    }
}

nonisolated private struct JellyfinLiveChannelDTO: Decodable, Sendable {
    let id: String
    let name: String
    let number: String?
    let callSign: String?
    let imageTags: [String: String]?
    let userData: JellyfinUserData?
    let isHD: Bool?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"; case name = "Name"; case number = "Number"; case callSign = "ChannelCallSign"
        case imageTags = "ImageTags"; case userData = "UserData"; case isHD = "IsHD"
    }
}

nonisolated private struct JellyfinLiveProgramDTO: Decodable, Sendable {
    let id: String
    let name: String
    let overview: String?
    let channelID: String?
    let seriesName: String?
    let seriesID: String?
    let startDate: String?
    let endDate: String?
    let imageTags: [String: String]?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let isLive: Bool?
    let isPremiere: Bool?
    let isSeries: Bool?
    let timerID: String?
    let seriesTimerID: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"; case name = "Name"; case overview = "Overview"; case channelID = "ChannelId"
        case seriesName = "SeriesName"; case seriesID = "SeriesId"; case startDate = "StartDate"; case endDate = "EndDate"
        case imageTags = "ImageTags"; case parentIndexNumber = "ParentIndexNumber"; case indexNumber = "IndexNumber"
        case isLive = "IsLive"; case isPremiere = "IsPremiere"; case isSeries = "IsSeries"; case timerID = "TimerId"; case seriesTimerID = "SeriesTimerId"; case status = "Status"
    }
}

nonisolated private struct JellyfinTimerDTO: Codable, Sendable {
    var id: String?
    var programID: String?
    var seriesTimerID: String?
    var channelID: String?
    var channelName: String?
    var name: String?
    var overview: String?
    var startDate: String?
    var endDate: String?
    var status: String?
    var prePaddingSeconds: Int?
    var postPaddingSeconds: Int?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"; case programID = "ProgramId"; case seriesTimerID = "SeriesTimerId"
        case channelID = "ChannelId"; case channelName = "ChannelName"; case name = "Name"; case overview = "Overview"
        case startDate = "StartDate"; case endDate = "EndDate"; case status = "Status"
        case prePaddingSeconds = "PrePaddingSeconds"; case postPaddingSeconds = "PostPaddingSeconds"
    }
}

nonisolated private struct JellyfinSeriesTimerDTO: Codable, Sendable {
    var id: String?
    var programID: String?
    var channelID: String?
    var name: String?
    var prePaddingSeconds: Int?
    var postPaddingSeconds: Int?
    var recordNewOnly: Bool?
    var recordAnyTime: Bool?
    var recordAnyChannel: Bool?
    var keepUpTo: Int?
    var keepUntil: String?
    var skipEpisodesInLibrary: Bool?

    var optionValues: [String: String] {
        [
            "prePaddingSeconds": String(prePaddingSeconds ?? 0),
            "postPaddingSeconds": String(postPaddingSeconds ?? 0),
            "recordNewOnly": String(recordNewOnly ?? false),
            "recordAnyTime": String(recordAnyTime ?? true),
            "recordAnyChannel": String(recordAnyChannel ?? false),
            "keepUpTo": String(keepUpTo ?? 0),
            "keepUntil": keepUntil ?? "UntilDeleted",
            "skipEpisodesInLibrary": String(skipEpisodesInLibrary ?? false),
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id"; case programID = "ProgramId"; case channelID = "ChannelId"; case name = "Name"
        case prePaddingSeconds = "PrePaddingSeconds"; case postPaddingSeconds = "PostPaddingSeconds"; case recordNewOnly = "RecordNewOnly"
        case recordAnyTime = "RecordAnyTime"; case recordAnyChannel = "RecordAnyChannel"; case keepUpTo = "KeepUpTo"
        case keepUntil = "KeepUntil"; case skipEpisodesInLibrary = "SkipEpisodesInLibrary"
    }
}

nonisolated private func parseBool(_ value: String?) -> Bool? {
    guard let value else { return nil }
    switch value.lowercased() {
    case "true", "1", "yes": return true
    case "false", "0", "no": return false
    default: return nil
    }
}
