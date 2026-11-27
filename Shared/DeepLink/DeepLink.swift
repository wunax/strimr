import Foundation

/// A `strimr://` link. Every entry point (URLs, Top Shelf, quick actions, App Intents, Spotlight, Handoff) builds one
/// and hands it to `DeepLinkRouter`.
///
/// ```text
/// strimr://open
/// strimr://media/<itemID>?provider=&server=[&type=]
/// strimr://media?type=movie|show&tmdb=|tvdb=|imdb=[&title=][&year=]
/// strimr://play/<itemID>?provider=&server=[&type=][&mode=resume|restart|shuffle]
/// strimr://play?type=movie|show&tmdb=|tvdb=|imdb=[&title=][&year=][&mode=]
/// strimr://live/<channel>[?provider=&server=]
/// strimr://library/<libraryID>?provider=&server=
/// strimr://search[?q=]
/// strimr://tab/<home|search|downloads|libraries|liveTV|explore|favorites>
/// ```
///
/// Every link may add `profile=`. Links end up on NFC tags and in home automations: parameters may be added, never
/// renamed or removed.
nonisolated struct DeepLink: Hashable, Sendable {
    static let scheme = "strimr"

    enum Destination: Hashable, Sendable {
        case open
        case media(MediaTarget)
        case play(MediaTarget, mode: PlayMode)
        case liveChannel(String, server: ServerIdentity?)
        case library(LibraryIdentity)
        case search(String?)
        case tab(Tab)
    }

    enum MediaTarget: Hashable, Sendable {
        case item(MediaIdentity, kind: MediaKind?)
        case catalog(CatalogTarget)
    }

    /// A movie or show by its catalog ids, found on whichever server of the profile has it.
    struct CatalogTarget: Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case movie
            case show
        }

        let kind: Kind
        let ids: ExternalIDs
        /// Only used to search the servers: the ids alone decide what matches.
        let title: String?
        let year: Int?

        init(kind: Kind, ids: ExternalIDs, title: String? = nil, year: Int? = nil) {
            self.kind = kind
            self.ids = ids
            self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            self.year = year
        }
    }

    enum PlayMode: String, Hashable, Sendable {
        case resume
        case restart
        case shuffle
    }

    enum Tab: String, Hashable, Sendable, CaseIterable {
        case home
        case search
        case downloads
        case libraries
        case liveTV
        case explore
        case favorites
    }

    let destination: Destination
    let profile: String?

    init(_ destination: Destination, profile: String? = nil) {
        self.destination = destination
        self.profile = profile?.nilIfEmpty
    }

    func withProfile(_ profile: String?) -> DeepLink {
        DeepLink(destination, profile: profile)
    }
}

// MARK: - Parsing

nonisolated extension DeepLink {
    /// Nil for any malformed link, another scheme, or an external player callback.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host()?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  query[item.name] == nil
            else { continue }
            query[item.name] = value
        }
        // Ids can hold a `/`, written as `%2F`, so the path is one component.
        let path = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding?.nilIfEmpty

        let destination: Destination? = switch host {
        case "open":
            .open
        case "media":
            Self.mediaTarget(path: path, query: query).map { .media($0) }
        case "play":
            if let mode = Self.playMode(query["mode"]), let target = Self.mediaTarget(path: path, query: query) {
                .play(target, mode: mode)
            } else {
                nil
            }
        case "live":
            if let path, let server = Self.optionalServer(query) {
                .liveChannel(path, server: server)
            } else {
                nil
            }
        case "library":
            if let path, let server = Self.server(query) {
                .library(LibraryIdentity(server: server, libraryID: path))
            } else {
                nil
            }
        case "search":
            .search(query["q"])
        case "tab":
            path.flatMap { name in
                Tab.allCases.first { $0.rawValue.lowercased() == name.lowercased() }
            }.map { .tab($0) }
        default:
            nil
        }
        guard let destination else { return nil }
        self.init(destination, profile: query["profile"])
    }

    private static func playMode(_ value: String?) -> PlayMode? {
        guard let value else { return .resume }
        return PlayMode(rawValue: value.lowercased())
    }

    private static func mediaTarget(path: String?, query: [String: String]) -> MediaTarget? {
        if let path {
            guard let server = server(query) else { return nil }
            return .item(MediaIdentity(server: server, itemID: path), kind: query["type"].flatMap(mediaKind))
        }
        guard let kind = query["type"].flatMap(catalogKind) else { return nil }
        let imdb = query["imdb"]?.lowercased()
        let tmdb = query["tmdb"]
        let tvdb = query["tvdb"]
        guard imdb.map(isIMDbID) ?? true, tmdb.map(isNumber) ?? true, tvdb.map(isNumber) ?? true else { return nil }
        let ids = ExternalIDs(imdb: imdb, tmdb: tmdb, tvdb: tvdb)
        guard !ids.isEmpty else { return nil }
        let year: Int?
        if let value = query["year"] {
            guard value.count == 4, isNumber(value) else { return nil }
            year = Int(value)
        } else {
            year = nil
        }
        return .catalog(CatalogTarget(kind: kind, ids: ids, title: query["title"], year: year))
    }

    /// The server a link names; `provider` defaults to Plex, as in the first Top Shelf links.
    private static func server(_ query: [String: String]) -> ServerIdentity? {
        guard let id = query["server"] else { return nil }
        let provider = query["provider"].map { MediaProvider(rawValue: $0.lowercased()) } ?? .plex
        return provider.map { ServerIdentity(provider: $0, id: id) }
    }

    /// `.some(nil)` when the link names no server, nil when it names one badly.
    private static func optionalServer(_ query: [String: String]) -> ServerIdentity?? {
        if query["server"] == nil {
            return query["provider"] == nil ? .some(nil) : nil
        }
        return server(query).map { .some($0) }
    }

    private static func mediaKind(_ value: String) -> MediaKind? {
        let value = value.lowercased()
        if value == "show" {
            return .series
        }
        guard let kind = MediaKind(rawValue: value), kind.isSupported else { return nil }
        return kind
    }

    private static func catalogKind(_ value: String) -> CatalogTarget.Kind? {
        switch value.lowercased() {
        case "movie": .movie
        case "show", "series": .show
        default: nil
        }
    }

    private static func isNumber(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(\.isASCIIDigit)
    }

    private static func isIMDbID(_ value: String) -> Bool {
        value.hasPrefix("tt") && isNumber(String(value.dropFirst(2)))
    }
}

// MARK: - Writing

nonisolated extension DeepLink {
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        var items: [URLQueryItem] = []
        switch destination {
        case .open:
            components.host = "open"
        case let .media(target):
            components.host = "media"
            Self.write(target, path: &components.percentEncodedPath, items: &items)
        case let .play(target, mode):
            components.host = "play"
            Self.write(target, path: &components.percentEncodedPath, items: &items)
            if mode != .resume {
                items.append(URLQueryItem(name: "mode", value: mode.rawValue))
            }
        case let .liveChannel(channel, server):
            components.host = "live"
            components.percentEncodedPath = Self.encodedPath(channel)
            if let server {
                items += Self.serverItems(server)
            }
        case let .library(library):
            components.host = "library"
            components.percentEncodedPath = Self.encodedPath(library.libraryID)
            items += Self.serverItems(library.server)
        case let .search(query):
            components.host = "search"
            if let query {
                items.append(URLQueryItem(name: "q", value: query))
            }
        case let .tab(tab):
            components.host = "tab"
            components.percentEncodedPath = Self.encodedPath(tab.rawValue)
        }
        if let profile {
            items.append(URLQueryItem(name: "profile", value: profile))
        }
        components.queryItems = items.isEmpty ? nil : items
        // `+` would read back as a space in some decoders.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    private static func write(_ target: MediaTarget, path: inout String, items: inout [URLQueryItem]) {
        switch target {
        case let .item(identity, kind):
            path = encodedPath(identity.itemID)
            items += serverItems(identity.server)
            if let kind {
                items.append(URLQueryItem(name: "type", value: kind.rawValue))
            }
        case let .catalog(catalog):
            items.append(URLQueryItem(name: "type", value: catalog.kind.rawValue))
            if let tmdb = catalog.ids.tmdb {
                items.append(URLQueryItem(name: "tmdb", value: tmdb))
            }
            if let tvdb = catalog.ids.tvdb {
                items.append(URLQueryItem(name: "tvdb", value: tvdb))
            }
            if let imdb = catalog.ids.imdb {
                items.append(URLQueryItem(name: "imdb", value: imdb))
            }
            if let title = catalog.title {
                items.append(URLQueryItem(name: "title", value: title))
            }
            if let year = catalog.year {
                items.append(URLQueryItem(name: "year", value: String(year)))
            }
        }
    }

    private static func encodedPath(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return "/" + (component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component)
    }

    private static func serverItems(_ server: ServerIdentity) -> [URLQueryItem] {
        [
            URLQueryItem(name: "provider", value: server.provider.rawValue),
            URLQueryItem(name: "server", value: server.id),
        ]
    }
}

private nonisolated extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
