import Foundation

// Shared with the Top Shelf extension: keep this file free of app-only types.

struct ExternalIDs: Codable, Hashable, Sendable {
    var imdb: String?
    var tmdb: String?
    var tvdb: String?

    init(imdb: String? = nil, tmdb: String? = nil, tvdb: String? = nil) {
        self.imdb = Self.normalized(imdb)
        self.tmdb = Self.normalized(tmdb)
        self.tvdb = Self.normalized(tvdb)
    }

    /// Plex `Guid` entries, e.g. `imdb://tt0111161`, `tmdb://278`, `tvdb://12345`.
    init(plexGuids: [String]) {
        var ids = ExternalIDs()
        for guid in plexGuids {
            let parts = guid.components(separatedBy: "://")
            guard parts.count == 2 else { continue }
            switch parts[0].lowercased() {
            case "imdb": ids.imdb = Self.normalized(parts[1])
            case "tmdb": ids.tmdb = Self.normalized(parts[1])
            case "tvdb": ids.tvdb = Self.normalized(parts[1])
            default: continue
            }
        }
        self = ids
    }

    /// Jellyfin `ProviderIds`, whose keys are `Imdb`, `Tmdb`, `Tvdb`.
    init(providerIDs: [String: String]) {
        var ids = ExternalIDs()
        for (key, value) in providerIDs {
            switch key.lowercased() {
            case "imdb": ids.imdb = Self.normalized(value)
            case "tmdb": ids.tmdb = Self.normalized(value)
            case "tvdb": ids.tvdb = Self.normalized(value)
            default: continue
            }
        }
        self = ids
    }

    var isEmpty: Bool {
        imdb == nil && tmdb == nil && tvdb == nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imdb = try container.decodeIfPresent(String.self, forKey: .imdb)
        tmdb = try container.decodeIfPresent(String.self, forKey: .tmdb)
        tvdb = try container.decodeIfPresent(String.self, forKey: .tvdb)
    }

    private enum CodingKeys: String, CodingKey {
        case imdb
        case tmdb
        case tvdb
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty,
              value != "0"
        else { return nil }
        return value
    }
}

/// What is known about a title to recognize it on another server.
struct MediaMatchDescriptor: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case movie
        case series
        case season
        case episode
        case other
    }

    let kind: Kind
    let guid: String?
    let externalIDs: ExternalIDs
    let seasonNumber: Int?
    let episodeNumber: Int?

    init(
        kind: Kind,
        guid: String?,
        externalIDs: ExternalIDs,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
    ) {
        self.kind = kind
        self.guid = guid
        self.externalIDs = externalIDs
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    /// Only agent guids are shared between Plex servers; `local://`, `agents.none://` and Jellyfin's own ids are not.
    var stableGuid: String? {
        guard let guid = guid?.lowercased(), guid.hasPrefix("plex://") else { return nil }
        return guid
    }

    /// Keys that identify the title across servers. Two descriptors sharing a key are the same title. The kind is part
    /// of every key because tmdb ids of movies and shows live in different namespaces.
    var matchKeys: Set<String> {
        guard kind != .other, kind != .season else { return [] }
        var keys = Set<String>()
        let scope = switch kind {
        case .movie: "movie"
        case .series: "series"
        case .episode: "episode"
        case .season, .other: ""
        }
        if let stableGuid {
            keys.insert("guid:\(stableGuid)")
        }
        let episodeSuffix = kind == .episode ? episodeNumberSuffix : ""
        if kind == .episode, episodeSuffix.isEmpty {
            return keys
        }
        if let imdb = externalIDs.imdb {
            keys.insert("imdb:\(scope):\(imdb)\(episodeSuffix)")
        }
        if let tmdb = externalIDs.tmdb {
            keys.insert("tmdb:\(scope):\(tmdb)\(episodeSuffix)")
        }
        if let tvdb = externalIDs.tvdb {
            keys.insert("tvdb:\(scope):\(tvdb)\(episodeSuffix)")
        }
        return keys
    }

    /// Episode ids are only trusted together with their season and episode numbers, which guards against providers
    /// that report the series ids on episodes.
    private var episodeNumberSuffix: String {
        guard let seasonNumber, let episodeNumber else { return "" }
        return ":s\(seasonNumber)e\(episodeNumber)"
    }
}

enum MediaMatching {
    /// Groups items that are the same title, keeping the order of first appearance for groups and their members.
    /// Items without any key stay alone: titles alone never match.
    static func group<Item>(_ items: [Item], descriptor: (Item) -> MediaMatchDescriptor) -> [[Item]] {
        var parent = Array(items.indices)

        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }

        var ownerByKey: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            for key in descriptor(item).matchKeys {
                if let owner = ownerByKey[key] {
                    let lhs = root(owner)
                    let rhs = root(index)
                    if lhs != rhs {
                        parent[max(lhs, rhs)] = min(lhs, rhs)
                    }
                } else {
                    ownerByKey[key] = index
                }
            }
        }

        var groups: [Int: [Item]] = [:]
        var order: [Int] = []
        for (index, item) in items.enumerated() {
            let groupRoot = root(index)
            if groups[groupRoot] == nil {
                order.append(groupRoot)
            }
            groups[groupRoot, default: []].append(item)
        }
        return order.compactMap { groups[$0] }
    }

    static func matches(_ lhs: MediaMatchDescriptor, _ rhs: MediaMatchDescriptor) -> Bool {
        !lhs.matchKeys.isDisjoint(with: rhs.matchKeys)
    }
}
