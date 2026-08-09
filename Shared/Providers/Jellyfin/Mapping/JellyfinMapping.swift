import Foundation

extension MediaItem {
    init(jellyfinItem: JellyfinItem, server: ServerIdentity) {
        let type: PlexItemType = switch jellyfinItem.kind {
        case .movie: .movie
        case .series: .show
        case .season: .season
        case .episode: .episode
        case .collection: .collection
        case .playlist: .playlist
        case .folder, .unknown: .unknown
        }
        let primaryPath = JellyfinArtworkPath.make(
            ownerID: jellyfinItem.id,
            type: "Primary",
            tag: jellyfinItem.imageTags?["Primary"]
        )
        let backdropPath = JellyfinArtworkPath.make(
            ownerID: jellyfinItem.id,
            type: "Backdrop",
            tag: jellyfinItem.backdropImageTags?.first
        )
        let seriesPath = JellyfinArtworkPath.make(
            ownerID: jellyfinItem.seriesID ?? jellyfinItem.id,
            type: "Primary",
            tag: jellyfinItem.seriesPrimaryImageTag
        )

        self.init(
            id: jellyfinItem.id,
            guid: "jellyfin://\(server.id)/\(jellyfinItem.id)",
            summary: jellyfinItem.overview,
            title: jellyfinItem.name,
            type: type,
            parentRatingKey: jellyfinItem.parentID,
            grandparentRatingKey: jellyfinItem.seriesID,
            genres: jellyfinItem.genres ?? [],
            year: jellyfinItem.productionYear,
            duration: jellyfinItem.duration,
            videoResolution: nil,
            rating: jellyfinItem.communityRating,
            ratings: [],
            contentRating: jellyfinItem.officialRating,
            studio: jellyfinItem.studios?.first?.name,
            tagline: jellyfinItem.taglines?.first,
            thumbPath: primaryPath,
            artPath: backdropPath ?? primaryPath,
            ultraBlurColors: nil,
            viewOffset: jellyfinItem.resumePosition,
            viewCount: jellyfinItem.userData?.played == true ? max(1, jellyfinItem.userData?.playCount ?? 1) : 0,
            childCount: jellyfinItem.childCount ?? jellyfinItem.recursiveItemCount,
            leafCount: jellyfinItem.recursiveItemCount,
            viewedLeafCount: nil,
            grandparentTitle: jellyfinItem.seriesName,
            parentTitle: jellyfinItem.seasonName,
            parentIndex: jellyfinItem.parentIndexNumber,
            index: jellyfinItem.indexNumber,
            grandparentThumbPath: seriesPath,
            grandparentArtPath: backdropPath,
            parentThumbPath: nil
        )
    }
}

extension MediaDisplayItem {
    init?(jellyfinItem: JellyfinItem, server: ServerIdentity) {
        let media = MediaItem(jellyfinItem: jellyfinItem, server: server)
        switch jellyfinItem.kind {
        case .movie, .series, .season, .episode:
            self = .playable(media)
        case .collection:
            self = .collection(
                CollectionMediaItem(
                    id: media.id,
                    key: media.id,
                    guid: media.guid,
                    type: .collection,
                    title: media.title,
                    summary: media.summary,
                    thumbPath: media.thumbPath,
                    childCount: media.childCount,
                    minYear: nil,
                    maxYear: nil
                )
            )
        case .playlist:
            self = .playlist(
                PlaylistMediaItem(
                    id: media.id,
                    key: media.id,
                    guid: media.guid,
                    type: .playlist,
                    title: media.title,
                    summary: media.summary,
                    compositePath: media.thumbPath,
                    duration: media.duration.map { Int($0 * 1000) },
                    leafCount: media.leafCount,
                    playlistType: "video"
                )
            )
        case .folder, .unknown:
            return nil
        }
    }
}

extension Library {
    init(jellyfinItem: JellyfinItem) {
        self.init(
            id: jellyfinItem.id,
            title: jellyfinItem.name,
            type: jellyfinItem.collectionType == "tvshows" ? .show : .movie
        )
    }
}

extension Person {
    init(jellyfinPerson: JellyfinPerson) {
        self.init(
            id: jellyfinPerson.id,
            name: jellyfinPerson.name,
            thumbPath: JellyfinArtworkPath.make(
                ownerID: jellyfinPerson.id,
                type: "Primary",
                tag: jellyfinPerson.primaryImageTag
            )
        )
    }
}

enum JellyfinArtworkPath {
    static func make(ownerID: String, type: String, tag: String?) -> String? {
        guard tag != nil else { return nil }
        return "jellyfin-artwork://\(ownerID)/\(type)?tag=\(tag ?? "")"
    }

    static func parse(_ value: String) -> (ownerID: String, type: String, tag: String?)? {
        guard let components = URLComponents(string: value),
              components.scheme == "jellyfin-artwork",
              let ownerID = components.host
        else { return nil }
        let type = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !type.isEmpty else { return nil }
        let tag = components.queryItems?.first(where: { $0.name == "tag" })?.value
        return (ownerID, type, tag)
    }
}
