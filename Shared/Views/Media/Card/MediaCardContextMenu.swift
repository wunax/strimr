import SwiftUI

/// Playback and navigation the card menus hand back to the app.
struct MediaCardActions {
    let play: (MediaItem, _ fromStart: Bool) -> Void
    let showMedia: (MediaItem) -> Void
}

extension EnvironmentValues {
    @Entry var mediaCardActions: MediaCardActions?
    /// Reloads the rows or page holding the card once a menu action changed its item, which can move it out of
    /// Continue Watching or change its badge.
    @Entry var reloadAfterMediaCardAction: ((MediaItem) -> Void)?
    /// Reloads the rows or page holding a playlist card once it was renamed or deleted from its menu.
    @Entry var reloadAfterPlaylistChange: ((ServerIdentity) -> Void)?
}

extension View {
    func mediaCardActions(
        registry: ServerRegistry,
        presenter: any PlaybackPresenting,
        showMedia: @escaping (MediaItem) -> Void,
    ) -> some View {
        environment(\.mediaCardActions, MediaCardActions(
            play: { item, fromStart in
                guard let services = registry.services(for: item.identity.server) else { return }
                Task {
                    await PlaybackLauncher(services: services, coordinator: presenter).play(
                        ratingKey: item.id,
                        type: item.type,
                        shouldResumeFromOffset: !fromStart,
                    )
                }
            },
            showMedia: showMedia,
        ))
    }

    func mediaCardContextMenu(_ media: MediaDisplayItem) -> some View {
        modifier(MediaCardContextMenu(media: media))
    }
}

private struct MediaCardContextMenu: ViewModifier {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?
    @Environment(\.mediaCardActions) private var actions
    @Environment(\.reloadAfterMediaCardAction) private var reload
    @Environment(\.reloadAfterPlaylistChange) private var reloadAfterPlaylistChange
    #if !os(tvOS)
        @Environment(DownloadManager.self) private var downloadManager
    #endif

    let media: MediaDisplayItem

    @State private var isPerforming = false
    @State private var failure: Failure?
    @State private var successCount = 0
    @State private var mediaToAddToPlaylist: MediaItem?
    @State private var isRenamingPlaylist = false
    @State private var isConfirmingPlaylistDeletion = false

    private struct Failure: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let message: String
    }

    func body(content: Content) -> some View {
        if let item = media.playableItem, let services, let actions {
            content
                .contextMenu {
                    menu(for: item, services: services, actions: actions)
                }
                .addToPlaylistPresentation(media: $mediaToAddToPlaylist, services: services)
                .modifier(FailureAlert(failure: $failure, successCount: successCount))
        } else if case let .playlist(playlist) = media, !playlist.isSmart, let services, isOnline(services) {
            content
                .contextMenu {
                    PlaylistManagementMenuItems(
                        isDisabled: isPerforming,
                        onRename: { isRenamingPlaylist = true },
                        onDelete: { isConfirmingPlaylistDeletion = true },
                    )
                }
                .playlistNamePrompt(
                    isPresented: $isRenamingPlaylist,
                    title: "playlist.rename.title",
                    confirmTitle: "playlist.rename.action",
                    initialName: playlist.title,
                ) { title in
                    changePlaylist(failureTitle: "playlist.error.rename", services: services) {
                        try await services.playlists.rename(playlistID: playlist.id, to: title)
                    }
                }
                .playlistDeleteConfirmation(isPresented: $isConfirmingPlaylistDeletion, playlistTitle: playlist.title) {
                    changePlaylist(failureTitle: "playlist.error.delete", services: services) {
                        try await services.playlists.delete(playlistID: playlist.id)
                    }
                }
                .modifier(FailureAlert(failure: $failure, successCount: successCount))
        } else {
            content
        }
    }

    private struct FailureAlert: ViewModifier {
        @Binding var failure: Failure?
        let successCount: Int

        func body(content: Content) -> some View {
            content
                .alert(item: $failure) { failure in
                    Alert(
                        title: Text(failure.title),
                        message: Text(failure.message),
                        dismissButton: .default(Text("common.actions.done")),
                    )
                }
            #if os(iOS)
                .sensoryFeedback(.success, trigger: successCount)
            #endif
        }
    }

    private func isOnline(_ services: MediaServices) -> Bool {
        #if os(tvOS)
            true
        #else
            !OfflineCoordinator.shared.isUnreachable(services.identity)
        #endif
    }

    private func changePlaylist(
        failureTitle: LocalizedStringKey,
        services: MediaServices,
        _ operation: @escaping () async throws -> Void,
    ) {
        guard !isPerforming else { return }
        isPerforming = true
        Task {
            defer { isPerforming = false }
            do {
                try await operation()
                services.notePlaylistsChanged()
                reloadAfterPlaylistChange?(services.identity)
                successCount += 1
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                failure = Failure(title: failureTitle, message: error.localizedDescription)
            }
        }
    }

    private var services: MediaServices? {
        registry.services(for: media, scoped: scopedServices)
    }

    @ViewBuilder
    private func menu(for item: MediaItem, services: MediaServices, actions: MediaCardActions) -> some View {
        let quickActions = MediaQuickActions(services: services)
        ForEach(
            quickActions.menuActions(
                for: item,
                canDownload: canDownload(item, services: services),
                canAddToPlaylist: isOnline(services),
            ),
            id: \.self,
        ) { action in
            Button {
                perform(action, on: item, quickActions: quickActions, services: services, actions: actions)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .disabled(isPerforming)
        }
    }

    private func canDownload(_ item: MediaItem, services: MediaServices) -> Bool {
        #if os(tvOS)
            false
        #else
            services.capabilities.downloads && downloadManager.status(for: item.identity) == nil
        #endif
    }

    private func perform(
        _ action: MediaQuickAction,
        on item: MediaItem,
        quickActions: MediaQuickActions,
        services: MediaServices,
        actions: MediaCardActions,
    ) {
        switch action {
        case .play, .resume:
            actions.play(item, false)
        case .playFromStart:
            actions.play(item, true)
        case .markWatched, .markUnwatched:
            run(failureTitle: "media.detail.watchAction.error.title", for: item) {
                await quickActions.setPlayed(action == .markWatched, for: item)
            }
        case .addFavorite, .removeFavorite:
            run(failureTitle: "media.detail.favorite.error.title", for: item) {
                await quickActions.setFavorite(action == .addFavorite, for: item)
            }
        case .goToSeries:
            show(id: item.type == .season ? item.parentRatingKey : item.grandparentRatingKey, services, actions)
        case .goToSeason:
            show(id: item.parentRatingKey, services, actions)
        case .addToPlaylist:
            mediaToAddToPlaylist = item
        case .download:
            download(item, services: services)
        }
    }

    /// One action at a time per card: a request made while another runs is ignored.
    private func run(
        failureTitle: LocalizedStringKey,
        for item: MediaItem,
        _ operation: @escaping () async -> MediaQuickActions.Outcome,
    ) {
        guard !isPerforming else { return }
        isPerforming = true
        Task {
            let outcome = await operation()
            isPerforming = false
            switch outcome {
            case .succeeded:
                successCount += 1
                reload?(item)
            case let .failed(message):
                failure = Failure(title: failureTitle, message: message)
            case .cancelled:
                break
            }
        }
    }

    private func show(id: String?, _ services: MediaServices, _ actions: MediaCardActions) {
        guard let id, !isPerforming else { return }
        isPerforming = true
        Task {
            defer { isPerforming = false }
            do {
                try await actions.showMedia(services.detail.mediaItem(id: id))
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
    }

    private func download(_ item: MediaItem, services: MediaServices) {
        #if !os(tvOS)
            guard !isPerforming else { return }
            isPerforming = true
            Task {
                if item.type == .season {
                    await downloadManager.enqueueItems(itemID: item.id, kind: .season, services: services)
                } else {
                    await downloadManager.enqueueItem(itemID: item.id, services: services)
                }
                isPerforming = false
                successCount += 1
            }
        #endif
    }
}
