import Foundation

extension DeepLink {
    /// The link "Copy Link" shares: a catalog link for a movie or show with an id, so it opens on any server that has
    /// the title, otherwise a link to the item on its own server.
    static func shareLink(for media: MediaItem, profile: String?) -> DeepLink? {
        switch media.type {
        case .movie, .series:
            let target: MediaTarget = catalogTarget(for: media).map { .catalog($0) }
                ?? .item(media.identity, kind: media.type)
            return DeepLink(.media(target), profile: profile)
        case .season, .episode:
            return DeepLink(.media(.item(media.identity, kind: media.type)), profile: profile)
        case .clip, .collection, .playlist, .folder, .unknown:
            return nil
        }
    }

    /// One id only, the one libraries of that kind are most often matched by, so the link stays short enough for an
    /// NFC tag.
    static func catalogTarget(for media: MediaItem) -> CatalogTarget? {
        let ids = media.externalIDs
        let kind: CatalogTarget.Kind
        let chosen: ExternalIDs?
        switch media.type {
        case .movie:
            kind = .movie
            chosen = ids.tmdb.map { ExternalIDs(tmdb: $0) }
                ?? ids.imdb.map { ExternalIDs(imdb: $0) }
                ?? ids.tvdb.map { ExternalIDs(tvdb: $0) }
        case .series:
            kind = .show
            chosen = ids.tvdb.map { ExternalIDs(tvdb: $0) }
                ?? ids.tmdb.map { ExternalIDs(tmdb: $0) }
                ?? ids.imdb.map { ExternalIDs(imdb: $0) }
        default:
            return nil
        }
        guard let chosen else { return nil }
        return CatalogTarget(kind: kind, ids: chosen, title: media.title, year: media.year)
    }

    static func liveChannelLink(_ channel: LiveTVChannel, server: ServerIdentity, profile: String?) -> DeepLink {
        DeepLink(.liveChannel(channel.providerID, server: server), profile: profile)
    }
}
