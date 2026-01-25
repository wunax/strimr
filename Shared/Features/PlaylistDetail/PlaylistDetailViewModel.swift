import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    @ObservationIgnored private let context: PlexAPIContext

    var playlist: PlaylistMediaItem
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var errorMessage: String?

    init(playlist: PlaylistMediaItem, context: PlexAPIContext) {
        self.playlist = playlist
        self.context = context
    }

    var playlistDisplayItem: MediaDisplayItem {
        .playlist(playlist)
    }

    var elementsCountText: String? {
        guard let leafCount = playlist.leafCount else { return nil }
        return String(localized: "media.labels.elementsCount \(leafCount)")
    }

    var durationText: String? {
        guard let duration = playlist.duration else { return nil }
        let durationSeconds = TimeInterval(duration) / 1000
        return durationSeconds.mediaDurationText()
    }

    func load() async {
        guard items.isEmpty else { return }
        await fetch()
    }

    private func fetch() async {
        guard let playlistRepository = try? PlaylistRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.loadDetails")
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let playlistResponse = playlistRepository.getPlaylist(ratingKey: playlist.id)
            async let itemsResponse = playlistRepository.getPlaylistItems(ratingKey: playlist.id)

            let playlistContainer = try await playlistResponse
            let itemsContainer = try await itemsResponse

            if let plexPlaylist = playlistContainer.mediaContainer.metadata?.first {
                playlist = PlaylistMediaItem(plexItem: plexPlaylist)
            }

            items = (itemsContainer.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }
}
