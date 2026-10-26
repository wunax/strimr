#if DEBUG
    import Foundation

    /// `catalog.json` as written by `scripts/demo-catalog/fetch_tmdb.py`.
    struct DemoCatalogFile: Decodable {
        struct Server: Decodable {
            let name: String
        }

        struct Row: Decodable {
            let id: String
            let kind: String?
            let title: String
            let items: [String]
        }

        struct LibraryEntry: Decodable {
            let id: String
            let title: String
            let type: String
            let items: [String]
            let recommended: [Row]
        }

        struct CastEntry: Decodable {
            let person: String
            let role: String?
        }

        struct Episode: Decodable {
            let id: String
            let number: Int
            let title: String?
            let summary: String?
            let airDate: String?
            let duration: TimeInterval?
            let still: String?
        }

        struct Season: Decodable {
            let id: String
            let number: Int
            let title: String?
            let summary: String?
            let episodeCount: Int?
            let poster: String?
            let episodes: [Episode]?
        }

        struct Resume: Decodable {
            let episode: String
            let progress: Double
        }

        struct Item: Decodable {
            let id: String
            let tmdbID: Int
            let type: String
            let library: String
            let title: String
            let tagline: String?
            let summary: String?
            let releaseDate: String?
            let year: Int?
            let genres: [String]
            let rating: Double?
            let contentRating: String?
            let studio: String?
            let cast: [CastEntry]
            let poster: String?
            let backdrop: String?
            let logo: String?
            let progress: Double?
            let duration: TimeInterval?
            let seasons: [Season]?
            let nextUp: String?
            let `continue`: Resume?
        }

        struct PersonEntry: Decodable {
            let id: String
            let name: String
            let photo: String?
        }

        struct Player: Decodable {
            let item: String
            let pauseAt: TimeInterval?
        }

        let server: Server
        let libraries: [LibraryEntry]
        let rows: [Row]
        let items: [Item]
        let people: [PersonEntry]
        let player: Player?
    }

    /// The demo catalog mapped to domain models, indexed by id.
    struct DemoCatalog {
        let serverName: String
        let libraries: [Library]
        let homeRows: [HomeRow]
        let player: DemoCatalogFile.Player?
        private let file: DemoCatalogFile
        private let server: ServerIdentity
        private let titles: [String: MediaItem]
        private let seasonsBySeries: [String: [MediaItem]]
        private let episodesBySeason: [String: [MediaItem]]
        private let items: [String: MediaItem]
        private let people: [String: DemoCatalogFile.PersonEntry]
        private let castByTitle: [String: [DemoCatalogFile.CastEntry]]
        private let recommendedByLibrary: [String: [DemoCatalogFile.Row]]

        enum LoadError: Error {
            case missingContentDirectory
        }

        /// Loads `catalog.<language>.json` for the app's language, falling back to `catalog.json`.
        static func load(server: ServerIdentity) throws -> DemoCatalog {
            guard let directory = DemoMode.contentDirectory else { throw LoadError.missingContentDirectory }
            let language = Locale.preferredLanguages.first
                .map { Locale(identifier: $0).language.languageCode?.identifier }
            let localized = language.flatMap(\.self).map { directory.appending(path: "catalog.\($0).json") }
            let url = localized.flatMap { FileManager.default.fileExists(atPath: $0.path()) ? $0 : nil }
                ?? directory.appending(path: "catalog.json")
            let file = try JSONDecoder().decode(DemoCatalogFile.self, from: Data(contentsOf: url))
            return DemoCatalog(file: file, server: server)
        }

        private init(file: DemoCatalogFile, server: ServerIdentity) {
            self.file = file
            self.server = server
            serverName = file.server.name
            player = file.player
            people = Dictionary(uniqueKeysWithValues: file.people.map { ($0.id, $0) })
            castByTitle = Dictionary(uniqueKeysWithValues: file.items.map { ($0.id, $0.cast) })
            recommendedByLibrary = Dictionary(uniqueKeysWithValues: file.libraries.map { ($0.id, $0.recommended) })
            libraries = file.libraries.map {
                Library(id: $0.id, title: $0.title, type: $0.type == "series" ? .series : .movie, server: server)
            }

            var titles: [String: MediaItem] = [:]
            var seasonsBySeries: [String: [MediaItem]] = [:]
            var episodesBySeason: [String: [MediaItem]] = [:]
            var items: [String: MediaItem] = [:]
            for entry in file.items {
                let title = Self.title(entry, server: server)
                titles[entry.id] = title
                items[entry.id] = title
                for season in entry.seasons ?? [] {
                    let seasonItem = Self.season(season, series: entry, server: server)
                    seasonsBySeries[entry.id, default: []].append(seasonItem)
                    items[season.id] = seasonItem
                    for episode in season.episodes ?? [] {
                        let progress = entry.continue?.episode == episode.id ? entry.continue?.progress : nil
                        let episodeItem = Self.episode(
                            episode,
                            season: season,
                            series: entry,
                            progress: progress,
                            server: server,
                        )
                        episodesBySeason[season.id, default: []].append(episodeItem)
                        items[episode.id] = episodeItem
                    }
                }
            }
            self.titles = titles
            self.seasonsBySeries = seasonsBySeries
            self.episodesBySeason = episodesBySeason
            self.items = items

            homeRows = file.rows.compactMap { row in
                let hub = Self.hub(row, server: server, items: row.items.compactMap { id in
                    Self.homeEntry(id: id, kind: row.kind, file: file, items: items)
                })
                guard hub.hasItems else { return nil }
                return switch row.kind {
                case "continueWatching": HomeRow.continueWatching(server: server, hub: hub)
                case "nextUp": HomeRow.nextUp(server: server, hub: hub)
                default: HomeRow.providerHub(server: server, hub: hub)
                }
            }
        }

        // MARK: - Lookups

        func item(id: String) -> MediaItem? {
            items[id]
        }

        func titles(in libraryID: String) -> [MediaItem] {
            file.libraries.first { $0.id == libraryID }?.items.compactMap { titles[$0] } ?? []
        }

        var allTitles: [MediaItem] {
            file.items.compactMap { titles[$0.id] }
        }

        func seasons(ofSeries seriesID: String) -> [MediaItem] {
            seasonsBySeries[seriesID] ?? []
        }

        func episodes(ofSeason seasonID: String) -> [MediaItem] {
            episodesBySeason[seasonID] ?? []
        }

        func episodes(ofSeries seriesID: String) -> [MediaItem] {
            seasons(ofSeries: seriesID).flatMap { episodes(ofSeason: $0.id) }
        }

        /// The episode a series opens on: the one in progress, then Next Up, then the first known episode.
        func onDeck(forSeries seriesID: String) -> MediaItem? {
            guard let entry = file.items.first(where: { $0.id == seriesID }) else { return nil }
            let id = entry.continue?.episode ?? entry.nextUp
            return id.flatMap { items[$0] } ?? episodes(ofSeries: seriesID).first
        }

        func recommendedHubs(in libraryID: String) -> [Hub] {
            (recommendedByLibrary[libraryID] ?? []).map { row in
                Self.hub(row, server: server, items: row.items.compactMap { titles[$0].map(MediaDisplayItem.playable) })
            }
        }

        func cast(for media: MediaItem) -> [CastMember] {
            let titleID = media.grandparentRatingKey ?? media.id
            return (castByTitle[titleID] ?? []).compactMap { entry in
                guard let person = people[entry.person] else { return nil }
                return CastMember(
                    id: person.id,
                    personID: person.id,
                    name: person.name,
                    character: entry.role,
                    thumbPath: person.photo,
                )
            }
        }

        func person(id: String) -> Person? {
            people[id].map { Person(id: $0.id, name: $0.name, thumbPath: $0.photo) }
        }

        func titles(withPerson personID: String) -> [MediaItem] {
            file.items.filter { $0.cast.contains { $0.person == personID } }.compactMap { titles[$0.id] }
        }

        // MARK: - Mapping

        private static func homeEntry(
            id: String,
            kind: String?,
            file: DemoCatalogFile,
            items: [String: MediaItem],
        ) -> MediaDisplayItem? {
            guard let entry = file.items.first(where: { $0.id == id }) else { return nil }
            let episodeID: String? = switch kind {
            case "continueWatching": entry.continue?.episode
            case "nextUp": entry.nextUp
            default: nil
            }
            return (episodeID.flatMap { items[$0] } ?? items[id]).map(MediaDisplayItem.playable)
        }

        private static func hub(_ row: DemoCatalogFile.Row, server: ServerIdentity, items: [MediaDisplayItem]) -> Hub {
            Hub(
                id: "demo.\(row.id)",
                key: "demo.\(row.id)",
                hubKey: nil,
                title: row.title,
                size: items.count,
                more: false,
                items: items,
                server: server,
            )
        }

        private static func title(_ entry: DemoCatalogFile.Item, server: ServerIdentity) -> MediaItem {
            let isSeries = entry.type == "series"
            let episodeCount = entry.seasons?.compactMap(\.episodeCount).reduce(0, +)
            let resumePosition = Self.resumePosition(progress: entry.progress, duration: entry.duration)
            return MediaItem(
                id: entry.id,
                identity: MediaIdentity(server: server, itemID: entry.id),
                guid: "demo://\(entry.id)",
                summary: entry.summary,
                title: entry.title,
                type: isSeries ? .series : .movie,
                parentRatingKey: nil,
                grandparentRatingKey: nil,
                genres: entry.genres,
                year: entry.year,
                releaseDate: entry.releaseDate.flatMap(date),
                duration: entry.duration,
                videoResolution: isSeries ? nil : "4k",
                rating: entry.rating,
                ratings: entry.rating.map { [MediaRating(source: .tmdb, value: $0)] } ?? [],
                contentRating: entry.contentRating,
                studio: entry.studio,
                tagline: entry.tagline,
                thumbPath: entry.poster,
                artPath: entry.backdrop,
                artworkCornerColors: nil,
                viewOffset: resumePosition,
                viewCount: 0,
                childCount: entry.seasons?.count,
                leafCount: episodeCount,
                viewedLeafCount: isSeries ? 0 : nil,
                watchState: watchState(resumePosition: resumePosition, unplayed: isSeries ? episodeCount : nil),
                grandparentTitle: nil,
                parentTitle: nil,
                parentIndex: nil,
                index: nil,
                grandparentThumbPath: nil,
                grandparentArtPath: nil,
                parentThumbPath: nil,
                librarySectionID: entry.library,
                externalIDs: ExternalIDs(providerIDs: ["Tmdb": String(entry.tmdbID)]),
                logoPath: entry.logo,
            )
        }

        private static func season(
            _ season: DemoCatalogFile.Season,
            series: DemoCatalogFile.Item,
            server: ServerIdentity,
        ) -> MediaItem {
            MediaItem(
                id: season.id,
                identity: MediaIdentity(server: server, itemID: season.id),
                guid: "demo://\(season.id)",
                summary: season.summary ?? series.summary,
                title: season.title ?? "\(season.number)",
                type: .season,
                parentRatingKey: series.id,
                grandparentRatingKey: series.id,
                genres: series.genres,
                year: nil,
                duration: nil,
                videoResolution: nil,
                rating: nil,
                ratings: [],
                contentRating: series.contentRating,
                studio: series.studio,
                tagline: nil,
                thumbPath: season.poster ?? series.poster,
                artPath: series.backdrop,
                artworkCornerColors: nil,
                viewOffset: nil,
                viewCount: 0,
                childCount: season.episodeCount,
                leafCount: season.episodeCount,
                viewedLeafCount: 0,
                watchState: watchState(resumePosition: nil, unplayed: season.episodeCount),
                grandparentTitle: series.title,
                parentTitle: series.title,
                parentIndex: nil,
                index: season.number,
                grandparentThumbPath: nil,
                grandparentArtPath: series.backdrop,
                parentThumbPath: nil,
                librarySectionID: series.library,
                grandparentLogoPath: series.logo,
            )
        }

        private static func episode(
            _ episode: DemoCatalogFile.Episode,
            season: DemoCatalogFile.Season,
            series: DemoCatalogFile.Item,
            progress: Double?,
            server: ServerIdentity,
        ) -> MediaItem {
            let resumePosition = Self.resumePosition(progress: progress, duration: episode.duration)
            return MediaItem(
                id: episode.id,
                identity: MediaIdentity(server: server, itemID: episode.id),
                guid: "demo://\(episode.id)",
                summary: episode.summary,
                title: episode.title ?? "\(episode.number)",
                type: .episode,
                parentRatingKey: season.id,
                grandparentRatingKey: series.id,
                genres: series.genres,
                year: episode.airDate.flatMap { Int($0.prefix(4)) },
                releaseDate: episode.airDate.flatMap(date),
                duration: episode.duration,
                videoResolution: "4k",
                rating: nil,
                ratings: [],
                contentRating: series.contentRating,
                studio: series.studio,
                tagline: nil,
                thumbPath: episode.still,
                artPath: series.backdrop,
                artworkCornerColors: nil,
                viewOffset: resumePosition,
                viewCount: 0,
                childCount: nil,
                leafCount: nil,
                viewedLeafCount: nil,
                watchState: watchState(resumePosition: resumePosition, unplayed: nil),
                grandparentTitle: series.title,
                parentTitle: season.title,
                parentIndex: season.number,
                index: episode.number,
                grandparentThumbPath: series.poster,
                grandparentArtPath: series.backdrop,
                parentThumbPath: season.poster,
                librarySectionID: series.library,
                grandparentLogoPath: series.logo,
            )
        }

        private static func watchState(resumePosition: TimeInterval?, unplayed: Int?) -> MediaWatchState {
            MediaWatchState(
                isPlayed: false,
                playCount: 0,
                resumePosition: resumePosition,
                unplayedItemCount: unplayed,
                isFavorite: false,
            )
        }

        private static func resumePosition(progress: Double?, duration: TimeInterval?) -> TimeInterval? {
            guard let progress, let duration else { return nil }
            return progress * duration
        }

        private static func date(_ value: String) -> Date? {
            try? Date(value, strategy: .iso8601.year().month().day())
        }
    }

#endif
