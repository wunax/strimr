import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    @ObservationIgnored private let service: any MediaDetailService

    var playlist: PlaylistMediaItem
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var errorMessage: String?
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(playlist: PlaylistMediaItem, services: MediaServices) {
        self.playlist = playlist
        service = services.detail
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await service.playlistItems(id: playlist.id)
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
