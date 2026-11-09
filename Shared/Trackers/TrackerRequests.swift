import Foundation

/// Builds the JSON bodies shared by Trakt and Simkl. `ids` returns nil for an item the service cannot address.
nonisolated enum TrackerRequestBody {
    typealias IDs = (TrackerItem) -> [String: Any]?

    /// `{"progress": 12.5, "movie": {"ids": …}}`, or `show` with a sibling `episode` for an episode.
    static func scrobble(item: TrackerItem, progress: Double, media: IDs) -> [String: Any]? {
        guard let identity = media(item) else { return nil }
        switch item.kind {
        case .movie:
            return ["progress": progress.trackerProgress, "movie": identity]
        case .episode:
            guard let season = item.season, let episode = item.episode else { return nil }
            return [
                "progress": progress.trackerProgress,
                "show": identity,
                "episode": ["season": season, "number": episode],
            ]
        }
    }

    /// Movies by ids, episodes nested as show, season, episode. An item that cannot be addressed is left out, and nil
    /// means nothing can be sent. Without dates, for a removal, no `watched_at` is sent.
    static func history(_ entries: [TrackerHistoryEntry], media: IDs) -> [String: Any]? {
        var movies: [[String: Any]] = []
        var shows: [String: (identity: [String: Any], seasons: [Int: [[String: Any]]])] = [:]
        var showOrder: [String] = []

        for entry in entries {
            guard var identity = media(entry.item) else { continue }
            let watchedAt = entry.watchedAt.map(Self.timestamp)
            switch entry.item.kind {
            case .movie:
                identity["watched_at"] = watchedAt
                movies.append(identity)
            case .episode:
                guard let season = entry.item.season, let episode = entry.item.episode else { continue }
                let key = entry.item.ids.seriesKey
                if shows[key] == nil {
                    shows[key] = (identity, [:])
                    showOrder.append(key)
                }
                var row: [String: Any] = ["number": episode]
                row["watched_at"] = watchedAt
                shows[key]?.seasons[season, default: []].append(row)
            }
        }
        guard !movies.isEmpty || !shows.isEmpty else { return nil }

        var body: [String: Any] = [:]
        if !movies.isEmpty {
            body["movies"] = movies
        }
        if !shows.isEmpty {
            body["shows"] = showOrder.compactMap { key -> [String: Any]? in
                guard let show = shows[key] else { return nil }
                var row = show.identity
                row["seasons"] = show.seasons.keys.sorted().map { season in
                    ["number": season, "episodes": show.seasons[season] ?? []] as [String: Any]
                }
                return row
            }
        }
        return body
    }

    private static func timestamp(_ date: Date) -> String {
        date.ISO8601Format()
    }
}

private extension ExternalIDs {
    nonisolated var seriesKey: String {
        [imdb ?? "", tmdb ?? "", tvdb ?? ""].joined(separator: "|")
    }
}

nonisolated extension URLRequest {
    static func trackerJSON(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: [String: Any]?,
    ) -> Self {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        }
        return request
    }

    static func trackerForm(url: URL, headers: [String: String], fields: [String: String]) -> Self {
        var request = trackerJSON(url: url, headers: headers, body: nil)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves `+` as is, and a form body reads it as a space.
        let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        request.httpBody = encoded.map { Data($0.utf8) }
        return request
    }
}

nonisolated struct TrackerHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
    let retryAfter: TimeInterval?

    var isSuccess: Bool {
        (200 ..< 300).contains(statusCode)
    }

    var bodyText: String {
        String(data: data, encoding: .utf8) ?? ""
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TrackerAPIError.invalidResponse
        }
    }
}

nonisolated struct TrackerHTTP: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> TrackerHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TrackerAPIError.invalidResponse }
        return TrackerHTTPResponse(
            statusCode: response.statusCode,
            data: data,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init),
        )
    }
}

nonisolated enum TrackerAppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var userAgent: String {
        "Strimr/\(version)"
    }
}
