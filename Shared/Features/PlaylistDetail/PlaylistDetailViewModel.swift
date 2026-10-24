import Foundation
import Observation

@MainActor
@Observable
final class PlaylistDetailViewModel {
    @ObservationIgnored private let services: MediaServices

    private(set) var playlist: PlaylistMediaItem
    private(set) var entries: [PlaylistEntry] = []
    /// True from the start, so the page does not call the playlist empty before the first load.
    var isLoading = true
    var errorMessage: String?
    /// False until the server confirms the user may change this playlist, and while offline.
    private(set) var canEdit = false
    /// One change at a time: each one is checked against the order the previous one left.
    private(set) var isMutating = false
    var actionFailure: PlaylistActionFailure?
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(playlist: PlaylistMediaItem, services: MediaServices) {
        self.playlist = playlist
        self.services = services
    }

    var playlistDisplayItem: MediaDisplayItem {
        .playlist(playlist)
    }

    var elementsCountText: String? {
        guard let count = entries.isEmpty ? playlist.leafCount : entries.count else { return nil }
        return String(localized: "media.labels.elementsCount \(count)")
    }

    var durationText: String? {
        let duration: TimeInterval? = if entries.isEmpty {
            playlist.duration.map { TimeInterval($0) / 1000 }
        } else {
            entries.compactMap { $0.media.playableItem?.duration }.reduce(0, +)
        }
        guard let duration, duration > 0 else { return nil }
        return duration.mediaDurationText()
    }

    var canMutate: Bool {
        canEdit && !isMutating
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await fetch(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard !isMutating, refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await fetch(preservingExistingContent: true)
    }

    func remove(_ entry: PlaylistEntry) async {
        guard canMutate, entries.contains(entry) else { return }
        await mutate(failureTitle: "playlist.error.remove") {
            // Where entry IDs repeat (Jellyfin 12), the server removes every occurrence.
            entries.removeAll { $0.entryID == entry.entryID }
        } operation: { [services, playlist] in
            try await services.playlists.remove(entry, fromPlaylist: playlist.id)
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) async {
        guard canMutate, source.count == 1, let sourceIndex = source.first,
              let result = PlaylistEntryMove.reordering(entries, from: sourceIndex, to: destination)
        else { return }
        await mutate(failureTitle: "playlist.error.move") {
            entries = result.entries
        } operation: { [services, playlist] in
            try await services.playlists.move(result.move, inPlaylist: playlist.id)
        }
    }

    /// - Parameter offset: -1 moves the entry up one position, 1 moves it down.
    func move(_ entry: PlaylistEntry, by offset: Int) async {
        guard let index = entries.firstIndex(of: entry), entries.indices.contains(index + offset) else { return }
        await move(fromOffsets: IndexSet(integer: index), toOffset: offset > 0 ? index + offset + 1 : index + offset)
    }

    func canMove(_ entry: PlaylistEntry, by offset: Int) -> Bool {
        guard canMutate, let index = entries.firstIndex(of: entry) else { return false }
        return entries.indices.contains(index + offset)
    }

    func rename(to title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canMutate, !title.isEmpty, title != playlist.title else { return }
        await mutate(failureTitle: "playlist.error.rename") {
            playlist = playlist.renamed(title)
        } operation: { [services, playlist] in
            try await services.playlists.rename(playlistID: playlist.id, to: title)
        }
    }

    /// Whether the playlist is gone, in which case the page should close.
    func delete() async -> Bool {
        guard canMutate else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.playlists.delete(playlistID: playlist.id)
            services.notePlaylistsChanged()
            return true
        } catch {
            report(error, failureTitle: "playlist.error.delete")
            return false
        }
    }

    /// Applies `change` right away and restores the previous state when the server refuses it.
    private func mutate(
        failureTitle: String.LocalizationValue,
        change: () -> Void,
        operation: @escaping () async throws -> Void,
    ) async {
        let previousEntries = entries
        let previousPlaylist = playlist
        isMutating = true
        change()
        defer { isMutating = false }
        do {
            try await operation()
            services.notePlaylistsChanged()
        } catch {
            entries = previousEntries
            playlist = previousPlaylist
            report(error, failureTitle: failureTitle)
        }
    }

    private func report(_ error: Error, failureTitle: String.LocalizationValue) {
        guard !Task.isCancelled, !error.isCancellation else { return }
        ErrorReporter.capture(error)
        actionFailure = PlaylistActionFailure(
            title: String(localized: failureTitle),
            message: error.localizedDescription,
        )
    }

    private func fetch(preservingExistingContent: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            entries = try await services.playlists.playlistEntries(id: playlist.id)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
            return
        }
        do {
            canEdit = try await services.playlists.canEdit(playlist)
        } catch {
            canEdit = false
        }
    }

    private func handleLoadError(_ message: String, preservingExistingContent: Bool) {
        if preservingExistingContent, !entries.isEmpty {
            errorMessage = nil
        } else {
            entries = []
            errorMessage = message
        }
    }
}

struct PlaylistActionFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
