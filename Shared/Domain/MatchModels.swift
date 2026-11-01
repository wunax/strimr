import Foundation

/// A title the server's agents found for a movie or series, to match it again.
struct MatchCandidate: Identifiable, Hashable, Sendable {
    enum Payload: Hashable, Sendable {
        case plex(guid: String)
        /// The Jellyfin `RemoteSearchResult`, sent back as received so no field the server needs is lost.
        case jellyfin(Data)
    }

    let id: String
    let title: String
    let year: Int?
    let posterURL: URL?
    let provider: String?
    /// The title the item is matched to now.
    let isCurrent: Bool
    let payload: Payload
}

nonisolated enum MetadataProviderName {
    /// Plex sends lowercase identifiers; Jellyfin sends display names, kept as they are.
    static func displayName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "plex": "Plex"
        case "tmdb", "themoviedb": "TMDB"
        case "tvdb", "thetvdb": "TVDB"
        case "imdb": "IMDb"
        case "fanarttv": "Fanart.tv"
        case "gracenote": "Gracenote"
        default: provider
        }
    }
}
