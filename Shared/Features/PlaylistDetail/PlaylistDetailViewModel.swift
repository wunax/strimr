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
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

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
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await fetch(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await fetch(preservingExistingContent: true)
    }

    private func fetch(preservingExistingContent: Bool) async {
        guard let playlistRepository = try? PlaylistRepository(context: context) else {
            handleLoadError(
                String(localized: "errors.selectServer.loadDetails"),
                preservingExistingContent: preservingExistingContent,
            )
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
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
        }
    }

    private func handleLoadError(_ message: String, preservingExistingContent: Bool) {
        if preservingExistingContent, !items.isEmpty {
            errorMessage = nil
            isLoading = false
        } else {
            items = []
            errorMessage = message
            isLoading = false
        }
    }
}
