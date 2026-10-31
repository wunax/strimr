#if os(iOS) || os(macOS)
    import Foundation

    @MainActor
    final class PlexDashboardRepository {
        private let context: PlexAPIContext
        private let network: PlexServerNetworkClient

        init(context: PlexAPIContext) {
            self.context = context
            network = PlexServerNetworkClient(context: context)
        }

        func sessions() async throws -> [PlexDashboardPlay] {
            try await container("/status/sessions").objects("Metadata").compactMap { play($0, live: true) }
        }

        func stopPlayback(sessionID: String, reason: String) async throws {
            guard !sessionID.isEmpty else { throw PlexAPIError.invalidResponse }
            try Task.checkCancellation()
            try await network.send(
                path: "/status/sessions/terminate",
                queryItems: [
                    URLQueryItem(name: "sessionId", value: sessionID),
                    URLQueryItem(name: "reason", value: reason),
                ],
                method: "POST",
            )
        }

        func users() async throws -> [PlexDashboardUser] {
            try await container("/accounts").objects("Account").compactMap { row in
                guard let id = row.string("id") else { return nil }
                let name = [row.string("name"), row.string("title")]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
                return PlexDashboardUser(
                    id: id,
                    name: name ?? String(localized: "plex.dashboard.unknownUser") + " · " + id,
                    thumb: row.string("thumb").flatMap { $0.isEmpty ? nil : $0 },
                    hasName: name != nil,
                )
            }
        }

        func resolvedUsers(_ users: [PlexDashboardUser]) async -> [PlexDashboardUser] {
            async let home = try? UserRepository(context: context).getHomeUsers()
            async let shared = try? sharedUserAvatars()
            let homeProfiles = await home?.users.map {
                PlexDashboardAvatarProfile(
                    id: $0.id.map(String.init),
                    name: $0.username ?? $0.title,
                    thumb: $0.thumb?.absoluteString,
                )
            } ?? []
            let profiles = await homeProfiles + (shared ?? [])
            return users.map { user in
                let exact = profiles.first { $0.id == user.id }
                let named = profiles
                    .filter { $0.name?.caseInsensitiveCompare(user.name) == .orderedSame && $0.thumb != nil }
                let matches = Set(named.compactMap(\.thumb))
                let resolvedName = exact?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasResolvedName = resolvedName?.isEmpty == false
                return PlexDashboardUser(
                    id: user.id,
                    name: user.hasName ? user.name : (hasResolvedName ? resolvedName! : user.name),
                    thumb: user.thumb ?? exact?.thumb ?? (matches.count == 1 ? matches.first : nil),
                    hasName: user.hasName || hasResolvedName,
                    isCurrentAccount: exact != nil,
                )
            }
        }

        private func sharedUserAvatars() async throws -> [PlexDashboardAvatarProfile] {
            guard let token = context.authTokenCloud else { return [] }
            var request = URLRequest(url: URL(string: "https://plex.tv/api/users")!)
            request.timeoutInterval = 15
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            request.setValue(context.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
            request.setValue("application/xml", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { return [] }
            try Task.checkCancellation()
            return PlexDashboardAvatarParser.profiles(from: data)
        }

        func libraries() async throws -> [PlexDashboardLibrary] {
            try await container("/library/sections").objects("Directory").compactMap { row in
                guard let id = row.string("key"), let title = row.string("title") else { return nil }
                return PlexDashboardLibrary(id: id, name: title)
            }
        }

        func history(
            start: Date?,
            accountID: String?,
            libraryID: String?,
            offset: Int,
        ) async throws -> PlexDashboardHistoryPage {
            let query = [
                URLQueryItem(name: "sort", value: "viewedAt:desc"),
                URLQueryItem.make("viewedAt>", start.map { Int($0.timeIntervalSince1970) }),
                URLQueryItem.make("accountID", accountID),
                URLQueryItem.make("librarySectionID", libraryID),
            ].compactMap(\.self)
            let result = try await container(
                "/status/sessions/history/all", query: query,
                headers: PlexPagination(start: offset, size: 200).headers,
            )
            let rows = result.objects("Metadata")
            let next = offset + rows.count
            return PlexDashboardHistoryPage(
                items: rows.compactMap { play($0, live: false) },
                nextOffset: next,
                hasMore: !rows.isEmpty && (result.number("totalSize").map { Double(next) < $0 } ?? (rows.count >= 200)),
            )
        }

        func bandwidth() async throws -> [PlexDashboardPoint] {
            let rows = try await container("/statistics/bandwidth", query: liveQuery).objects("StatisticsBandwidth")
            let local = String(localized: "plex.dashboard.local")
            let remote = String(localized: "plex.dashboard.remote")
            var sums: [String: PlexDashboardPoint] = [:]
            for row in rows {
                guard row.number("timespan") == 6, let at = row.number("at"),
                      let bytes = row.number("bytes") else { continue }
                let series = row.number("lan") == 1 ? local : remote
                let key = "\(at)|\(series)"
                // Plex's live bandwidth buckets cover one second. Bytes become megabits per second.
                sums[key] = PlexDashboardPoint(
                    date: Date(timeIntervalSince1970: at),
                    series: series,
                    value: (sums[key]?.value ?? 0) + max(0, bytes) * 8 / 1_000_000,
                )
            }
            let dates = Set(sums.values.map(\.date)).sorted()
            return dates.flatMap { date in
                [local, remote].map { series in
                    sums["\(date.timeIntervalSince1970)|\(series)"]
                        ?? PlexDashboardPoint(date: date, series: series, value: 0)
                }
            }
        }

        func resources() async throws -> (cpu: [PlexDashboardPoint], memory: [PlexDashboardPoint]) {
            let rows = try await container("/statistics/resources", query: liveQuery).objects("StatisticsResources")
            let host = String(localized: "plex.dashboard.host")
            let process = String(localized: "plex.dashboard.process")
            var cpu: [PlexDashboardPoint] = []
            var memory: [PlexDashboardPoint] = []
            for row in rows {
                guard row.number("timespan") == 6, let at = row.number("at") else { continue }
                let date = Date(timeIntervalSince1970: at)
                for (field, series) in [("hostCpuUtilization", host), ("processCpuUtilization", process)] {
                    if let value = row.number(field) {
                        cpu.append(.init(date: date, series: series, value: value))
                    }
                }
                for (field, series) in [("hostMemoryUtilization", host), ("processMemoryUtilization", process)] {
                    if let value = row.number(field) {
                        memory.append(.init(date: date, series: series, value: value))
                    }
                }
            }
            return (cpu.sorted { $0.date < $1.date }, memory.sorted { $0.date < $1.date })
        }

        func activity(start: Date) async throws -> [PlexDashboardActivity] {
            let rows = try await container("/statistics/media", query: [
                URLQueryItem(name: "timespan", value: "3"),
                URLQueryItem(name: "at>", value: String(Int(start.timeIntervalSince1970))),
            ]).objects("StatisticsMedia")
            return rows.compactMap { row in
                guard row.number("timespan") == 3, let at = row.number("at"),
                      at >= start.timeIntervalSince1970, let accountID = row.string("accountID"),
                      let duration = row.number("duration"), let type = row.number("metadataType")
                else { return nil }
                return PlexDashboardActivity(
                    date: Date(timeIntervalSince1970: at),
                    accountID: accountID,
                    kind: .init(metadataType: Int(type)),
                    plays: Int(row.number("count") ?? 0),
                    duration: max(0, duration),
                )
            }
        }

        func avatarURL(_ path: String?) -> URL? {
            guard let path, !path.isEmpty else { return nil }
            if let url = URL(string: path), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
            guard path.hasPrefix("/") else { return nil }
            return try? ImageRepository(context: context).transcodeImageURL(path: path, width: 80, height: 80)
        }

        func artworkURL(_ path: String?, size: Int = 160) -> URL? {
            guard let path else { return nil }
            return try? ImageRepository(context: context).transcodeImageURL(
                path: path,
                width: size,
                height: size * 3 / 2,
            )
        }

        private var liveQuery: [URLQueryItem] {
            [
                URLQueryItem(name: "timespan", value: "6"),
                URLQueryItem(name: "at>", value: String(Int(Date().addingTimeInterval(-120).timeIntervalSince1970))),
            ]
        }

        private func container(
            _ path: String,
            query: [URLQueryItem] = [],
            headers: [String: String] = [:],
        ) async throws -> [String: Any] {
            let result = try await network.json(path: path, queryItems: query, headers: headers)
            guard let container = result["MediaContainer"] as? [String: Any] else { throw PlexAPIError.invalidResponse }
            return container
        }

        private func play(_ row: [String: Any], live: Bool) -> PlexDashboardPlay? {
            guard let title = row.string("title") else { return nil }
            let ratingKey = row.string("ratingKey") ?? metadataID(row.string("key")) ?? ""
            let kind = PlexDashboardMediaKind(type: row.string("type") ?? "")
            let user = row["User"] as? [String: Any] ?? [:]
            let player = row["Player"] as? [String: Any] ?? [:]
            let transcode = row["TranscodeSession"] as? [String: Any] ?? [:]
            let versions = row.objects("Media")
            let media = versions.first { $0.number("selected") == 1 } ?? versions.first ?? [:]
            let parts = media.objects("Part")
            let part = parts.first { $0.number("selected") == 1 } ?? parts.first ?? [:]
            let accountID = row.string("accountID") ?? user.string("id")
            let viewedAt = row.number("viewedAt").map(Date.init(timeIntervalSince1970:))
            let id = live ? row.string("sessionKey") : row.string("historyKey")
            let groupTitle = row.string("grandparentTitle")
            let subtitle: String? = if kind == .episode, let season = row.string("parentIndex"),
                                       let episode = row.string("index")
            {
                "S\(season) · E\(episode) · \(title)"
            } else if groupTitle != nil {
                title
            } else {
                row.string("year")
            }
            let duration = row.number("duration") ?? 0
            let decision = transcode.string("videoDecision") == "transcode" || transcode.string("audioDecision") == "transcode"
                ? "transcode" : (part.string("decision") ?? (transcode.isEmpty ? "directplay" : "copy"))
            return PlexDashboardPlay(
                id: id ?? "\(ratingKey)|\(viewedAt?.timeIntervalSince1970 ?? 0)|\(accountID ?? "")",
                ratingKey: ratingKey,
                groupKey: row.string("grandparentRatingKey") ?? metadataID(row.string("grandparentKey")) ?? ratingKey,
                title: groupTitle ?? title, subtitle: subtitle, kind: kind,
                thumb: row.string("grandparentThumb") ?? row.string("thumb"),
                accountID: accountID, userName: user.string("title"), userThumb: user.string("thumb"),
                viewedAt: viewedAt,
                player: player.string("title"), state: player.string("state"), decision: live ? decision : nil,
                progress: duration > 0 ? min(1, max(0, (row.number("viewOffset") ?? 0) / duration)) : nil,
                sessionID: live ? (row["Session"] as? [String: Any])?.string("id") : nil,
                streamDetails: live ? streamDetails(
                    row: row,
                    player: player,
                    media: media,
                    part: part,
                    transcode: transcode,
                ) : [],
            )
        }

        private func metadataID(_ path: String?) -> String? {
            guard let path, path.hasPrefix("/library/metadata/") else { return nil }
            return path.dropFirst("/library/metadata/".count).split(separator: "/").first.map(String.init)
        }

        private func streamDetails(
            row: [String: Any], player: [String: Any], media: [String: Any],
            part: [String: Any], transcode: [String: Any],
        ) -> [PlexDashboardStreamDetail] {
            var details: [PlexDashboardStreamDetail] = []
            func add(_ field: PlexDashboardStreamField, _ value: String?) {
                guard let value, !value.isEmpty else { return }
                details.append(.init(field: field, value: value))
            }
            let decision = PlexDashboardFormatting.decision
            add(.app, [player.string("product"), player.string("platform")].compactMap(\.self).joined(separator: " · "))
            add(.state, PlexDashboardFormatting.playbackState(player.string("state")))
            let time = DateComponentsFormatter()
            time.allowedUnits = [.hour, .minute, .second]
            time.unitsStyle = .positional
            time.zeroFormattingBehavior = .pad
            if let duration = row.number("duration"), duration > 0 {
                let position = time.string(from: max(0, row.number("viewOffset") ?? 0) / 1000) ?? ""
                add(.position, "\(position) / \(time.string(from: duration / 1000) ?? "")")
            }
            let session = row["Session"] as? [String: Any] ?? [:]
            let location = session.string("location")
            let local = String(localized: "plex.dashboard.local")
            let remote = String(localized: "plex.dashboard.remote")
            if player.number("relayed") == 1 {
                add(.connection, String(localized: "plex.dashboard.stream.relay"))
            } else if let isLocal = player.number("local") {
                add(.connection, isLocal == 1 ? local : remote)
            } else if let location, ["lan", "wan"].contains(location) {
                add(.connection, location == "lan" ? local : remote)
            }
            if let secure = player.number("secure") {
                add(
                    .security,
                    secure == 1
                        ? String(localized: "plex.dashboard.stream.secure")
                        : String(localized: "plex.dashboard.stream.insecure"),
                )
            }
            add(.address, player.string("address"))
            if let bandwidth = session.number("bandwidth") {
                add(.bandwidth, PlexDashboardFormatting.bandwidth(bandwidth / 1000))
            }
            let streams = part.objects("Stream")
            let video = streams.first { $0.number("streamType") == 1 }
            let audioStreams = streams.filter { $0.number("streamType") == 2 }
            let audio = audioStreams
                .first { $0.number("selected") == 1 } ?? (audioStreams.count == 1 ? audioStreams.first : nil)
            let subtitle = streams.first { $0.number("streamType") == 3 && $0.number("selected") == 1 }
            add(.video, video?.string("displayTitle") ?? media.string("videoCodec")?.uppercased())
            add(
                .videoMode,
                decision(transcode.string("videoDecision") ?? video?.string("decision") ?? part.string("decision")),
            )
            if transcode.string("videoDecision") == "transcode" {
                add(
                    .videoOutput,
                    [transcode.string("height").map { $0 + "p" }, transcode.string("videoCodec")?.uppercased()]
                        .compactMap(\.self).joined(separator: " · "),
                )
            }
            add(.audio, audio?.string("displayTitle") ?? media.string("audioCodec")?.uppercased())
            add(
                .audioMode,
                decision(transcode.string("audioDecision") ?? audio?.string("decision") ?? part.string("decision")),
            )
            if transcode.string("audioDecision") == "transcode" {
                add(.audioOutput, transcode.string("audioCodec")?.uppercased())
            }
            add(.subtitles, subtitle?.string("displayTitle"))
            add(.subtitleMode, decision(subtitle?.string("decision") ?? transcode.string("subtitleDecision")))
            // A hardware request alone does not establish that hardware is actually in use.
            add(
                .hardwareDecode,
                transcode.string("transcodeHwDecodingTitle") ?? transcode.string("transcodeHwDecoding"),
            )
            add(
                .hardwareEncode,
                transcode.string("transcodeHwEncodingTitle") ?? transcode.string("transcodeHwEncoding"),
            )
            return details
        }
    }

    private extension [String: Any] {
        func string(_ key: String) -> String? {
            if let value = self[key] as? String {
                return value
            }
            return (self[key] as? NSNumber)?.stringValue
        }

        func number(_ key: String) -> Double? {
            if let value = self[key] as? NSNumber {
                return value.doubleValue
            }
            return (self[key] as? String).flatMap(Double.init)
        }

        func objects(_ key: String) -> [[String: Any]] {
            if let values = self[key] as? [[String: Any]] {
                return values
            }
            if let value = self[key] as? [String: Any] {
                return [value]
            }
            return []
        }
    }

    private nonisolated struct PlexDashboardAvatarProfile {
        let id: String?
        let name: String?
        let thumb: String?
    }

    private final nonisolated class PlexDashboardAvatarParser: NSObject, XMLParserDelegate {
        private var profiles: [PlexDashboardAvatarProfile] = []

        static func profiles(from data: Data) -> [PlexDashboardAvatarProfile] {
            let delegate = PlexDashboardAvatarParser()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            return parser.parse() ? delegate.profiles : []
        }

        func parser(
            _: XMLParser,
            didStartElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes: [String: String],
        ) {
            guard elementName == "User" else { return }
            profiles.append(.init(
                id: attributes["id"],
                name: attributes["username"] ?? attributes["title"],
                thumb: attributes["thumb"].flatMap { $0.isEmpty ? nil : $0 },
            ))
        }
    }

#endif
