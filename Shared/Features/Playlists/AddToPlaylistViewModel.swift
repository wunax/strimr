import Foundation
import Observation

@MainActor
@Observable
final class AddToPlaylistViewModel {
    let media: MediaItem
    @ObservationIgnored private let services: MediaServices

    private(set) var playlists: [PlaylistMediaItem] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isSaving = false
    var failure: PlaylistActionFailure?

    init(media: MediaItem, services: MediaServices) {
        self.media = media
        self.services = services
    }

    /// Series and seasons are left out: the servers copy their current episodes, so later ones would be missing.
    static func canAdd(_ media: MediaItem) -> Bool {
        [.movie, .episode].contains(media.type)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            playlists = try await services.playlists.editablePlaylists()
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    /// Whether the media was added, in which case the picker should close.
    func add(to playlist: PlaylistMediaItem) async -> Bool {
        await save(failureTitle: "playlist.error.add") { [services, media] in
            try await services.playlists.add(itemID: media.id, toPlaylist: playlist.id)
        }
    }

    /// Whether the playlist was created with the media in it, in which case the picker should close.
    func createPlaylist(named title: String) async -> Bool {
        guard !title.isEmpty else { return false }
        return await save(failureTitle: "playlist.error.create") { [services, media] in
            try await services.playlists.createPlaylist(title: title, itemID: media.id)
        }
    }

    private func save(
        failureTitle: String.LocalizationValue,
        _ operation: @escaping () async throws -> Void,
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
            services.notePlaylistsChanged()
            return true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return false }
            ErrorReporter.capture(error)
            failure = PlaylistActionFailure(title: String(localized: failureTitle), message: error.localizedDescription)
            return false
        }
    }
}
