import Foundation

enum MediaQuickAction: Hashable {
    case showDetails
    case play
    case resume
    case playFromStart
    case markWatched
    case markUnwatched
    case addFavorite
    case removeFavorite
    case addToPlaylist
    case goToSeries
    case goToSeason
    case download
    case removeFromContinueWatching
    /// Opens the server administration actions of `MediaQuickActions.manageActions(for:)`.
    case manage
    case refreshMetadata
    case analyze
    case editArtwork
    case delete
    /// Plex wording of the match search.
    case fixMatch
    /// Jellyfin wording of the match search.
    case identify
    case unmatch

    var title: String {
        switch self {
        case .showDetails: String(localized: "media.quickActions.showDetails")
        case .play: String(localized: "common.actions.play")
        case .resume: String(localized: "common.actions.resume")
        case .playFromStart: String(localized: "common.actions.playFromStart")
        case .markWatched: String(localized: "media.detail.watchAction.markWatched")
        case .markUnwatched: String(localized: "media.detail.watchAction.markUnwatched")
        case .addFavorite: String(localized: "media.detail.favorite.add")
        case .removeFavorite: String(localized: "media.detail.favorite.remove")
        case .addToPlaylist: String(localized: "playlist.add.menuTitle")
        case .goToSeries: String(localized: "media.quickActions.goToSeries")
        case .goToSeason: String(localized: "media.quickActions.goToSeason")
        case .download: String(localized: "downloads.action")
        case .removeFromContinueWatching: String(localized: "media.quickActions.removeFromContinueWatching")
        case .manage: String(localized: "media.manage.title")
        case .refreshMetadata: String(localized: "media.manage.refreshMetadata")
        case .analyze: String(localized: "media.manage.analyze")
        case .editArtwork: String(localized: "media.manage.editArtwork")
        case .delete: String(localized: "media.manage.delete")
        case .fixMatch: String(localized: "media.manage.fixMatch")
        case .identify: String(localized: "media.manage.identify")
        case .unmatch: String(localized: "media.manage.unmatch")
        }
    }

    var systemImage: String {
        switch self {
        case .showDetails: "info.circle"
        case .play, .resume: "play.fill"
        case .playFromStart: "arrow.counterclockwise"
        case .markWatched: "checkmark.circle"
        case .markUnwatched: "checkmark.circle.fill"
        case .addFavorite: "star"
        case .removeFavorite: "star.fill"
        case .addToPlaylist: "text.badge.plus"
        case .goToSeries: "tv"
        case .goToSeason: "rectangle.stack"
        case .download: "arrow.down.circle"
        case .removeFromContinueWatching: "minus.circle"
        case .manage: "wrench.and.screwdriver"
        case .refreshMetadata: "arrow.clockwise"
        case .analyze: "waveform.badge.magnifyingglass"
        case .editArtwork: "photo.on.rectangle"
        case .delete: "trash"
        case .fixMatch, .identify: "magnifyingglass"
        case .unmatch: "link.badge.minus"
        }
    }
}

/// Watched and favorite actions shared by the detail page and the card menus, so both make the same calls and
/// report failures the same way.
@MainActor
struct MediaQuickActions {
    enum Outcome: Equatable {
        case succeeded
        case failed(message: String)
        case cancelled
    }

    enum DeletionPreparation: Equatable {
        case ready(MediaDeletionImpact)
        case failed(message: String)
        case cancelled
    }

    private let supportsFavorites: Bool
    private let setPlayedHandler: (Bool, String) async throws -> Void
    private let setFavoriteHandler: (Bool, MediaItem) async throws -> Void
    private let removeFromContinueWatchingHandler: ((String) async throws -> Void)?
    private let didChange: () -> Void
    private let management: Management?

    /// Present only when the user manages the server's library or can delete its media.
    struct Management {
        var canManageLibrary = true
        var canDelete = false
        var supportsAnalyze: Bool
        var refreshMetadata: (String) async throws -> Void
        var analyze: (String) async throws -> Void
        /// The server applies the update in the background, after the call returns.
        var updateStarted: (String) -> Void = { _ in }
        var artworkKinds: (MediaItem) -> [EditableArtworkKind] = { _ in [] }
        var artworkPicker: (MediaItem) -> ArtworkPickerViewModel? = { _ in nil }
        var deletionImpact: (MediaItem) async throws -> MediaDeletionImpact = { _ in .files(count: 0, totalSize: nil) }
        var delete: (MediaItem) async throws -> Void = { _ in }
        var deleted: (String) -> Void = { _ in }
        var matchSearch: (MediaItem) -> MatchSearchViewModel? = { _ in nil }
        /// Plex can also detach an item from its match; it names the search "fix match", Jellyfin "identify".
        var supportsUnmatch = false
        var unmatch: (String) async throws -> Void = { _ in }
    }

    init(services: MediaServices) {
        supportsFavorites = services.capabilities.favorites
        setPlayedHandler = { played, itemID in try await services.detail.setPlayed(played, itemID: itemID) }
        setFavoriteHandler = { favorite, media in try await services.favorites.setFavorite(favorite, media: media) }
        removeFromContinueWatchingHandler = services.home.supportsContinueWatchingRemoval
            ? { itemID in try await services.home.removeFromContinueWatching(itemID: itemID) }
            : nil
        didChange = { services.noteWatchStateChanged() }
        let service = services.management
        let authorization = services.authorization
        management = authorization.canManageLibrary || authorization.canDeleteMedia
            ? Management(
                canManageLibrary: authorization.canManageLibrary,
                canDelete: authorization.canDeleteMedia,
                supportsAnalyze: service.supportsAnalyze,
                refreshMetadata: { try await service.refreshMetadata(itemID: $0) },
                analyze: { try await service.analyze(itemID: $0) },
                updateStarted: { services.noteMediaChangeScheduled(itemID: $0) },
                artworkKinds: { service.artworkKinds(for: $0) },
                artworkPicker: { item in
                    let kinds = service.artworkKinds(for: item)
                    guard !kinds.isEmpty else { return nil }
                    return ArtworkPickerViewModel(item: item, kinds: kinds, service: service) {
                        services.noteMediaChanged(itemID: $0)
                    }
                },
                deletionImpact: { try await service.deletionImpact(of: $0) },
                delete: { try await service.delete($0) },
                deleted: { services.noteMediaDeleted(itemID: $0) },
                matchSearch: { item in
                    MatchSearchViewModel(
                        item: item,
                        search: { try await service.searchMatches(for: item, title: $0, year: $1) },
                        apply: { try await service.applyMatch($0, to: item) },
                    ) { services.noteMediaChangeScheduled(itemID: $0) }
                },
                supportsUnmatch: service.supportsUnmatch,
                unmatch: { try await service.unmatch(itemID: $0) },
            )
            : nil
    }

    init(
        supportsFavorites: Bool,
        setPlayed: @escaping (Bool, String) async throws -> Void,
        setFavorite: @escaping (Bool, MediaItem) async throws -> Void,
        removeFromContinueWatching: ((String) async throws -> Void)? = nil,
        didChange: @escaping () -> Void = {},
        management: Management? = nil,
    ) {
        self.supportsFavorites = supportsFavorites
        setPlayedHandler = setPlayed
        setFavoriteHandler = setFavorite
        removeFromContinueWatchingHandler = removeFromContinueWatching
        self.didChange = didChange
        self.management = management
    }

    func canFavorite(_ item: MediaItem) -> Bool {
        supportsFavorites && [.movie, .series, .season, .episode].contains(item.type)
    }

    /// Series and seasons have no play entry: what to play first is only known once the detail page has loaded.
    /// `isInContinueWatching` is set only for the cards of the home's Continue Watching row.
    /// `canManage` is false while the server is unreachable.
    func menuActions(
        for item: MediaItem,
        canDownload: Bool,
        canAddToPlaylist: Bool = false,
        offersDetails: Bool = false,
        isInContinueWatching: Bool = false,
        canManage: Bool = false,
    ) -> [MediaQuickAction] {
        var actions: [MediaQuickAction] = []
        let hasProgress = (item.viewOffset ?? 0) > 0
        if offersDetails, [.movie, .episode, .clip].contains(item.type) {
            actions.append(.showDetails)
        }
        if [.movie, .episode, .clip].contains(item.type) {
            actions.append(hasProgress ? .resume : .play)
            if hasProgress {
                actions.append(.playFromStart)
            }
        }
        if [.movie, .series, .season, .episode].contains(item.type) {
            // Like the detail page, an item in progress offers both: marking it unwatched clears its progress.
            if hasProgress, !item.isFullyWatched {
                actions.append(contentsOf: [.markWatched, .markUnwatched])
            } else {
                actions.append(item.isFullyWatched ? .markUnwatched : .markWatched)
            }
        }
        if canFavorite(item) {
            actions.append(item.watchState.isFavorite ? .removeFavorite : .addFavorite)
        }
        if canAddToPlaylist, AddToPlaylistViewModel.canAdd(item) {
            actions.append(.addToPlaylist)
        }
        if item.type == .episode, item.grandparentRatingKey != nil {
            actions.append(.goToSeries)
        }
        if item.type == .episode, item.parentRatingKey != nil {
            actions.append(.goToSeason)
        }
        if item.type == .season, item.parentRatingKey != nil {
            actions.append(.goToSeries)
        }
        if canDownload, [.movie, .episode, .season].contains(item.type) {
            actions.append(.download)
        }
        if isInContinueWatching, removeFromContinueWatchingHandler != nil,
           [.movie, .episode].contains(item.type)
        {
            actions.append(.removeFromContinueWatching)
        }
        if canManage, !manageActions(for: item).isEmpty {
            actions.append(.manage)
        }
        return actions
    }

    /// The entries of the Manage submenu; empty when the user does not manage the server.
    func manageActions(for item: MediaItem) -> [MediaQuickAction] {
        guard let management, [.movie, .series, .season, .episode].contains(item.type) else { return [] }
        var actions: [MediaQuickAction] = []
        if management.canManageLibrary {
            actions.append(.refreshMetadata)
            if management.supportsAnalyze {
                actions.append(.analyze)
            }
            if !management.artworkKinds(item).isEmpty {
                actions.append(.editArtwork)
            }
            if Self.canMatch(item) {
                actions.append(management.supportsUnmatch ? .fixMatch : .identify)
                // Plex gives unmatched items a `local://` guid.
                if management.supportsUnmatch, !item.guid.hasPrefix("local://") {
                    actions.append(.unmatch)
                }
            }
        }
        if management.canDelete {
            actions.append(.delete)
        }
        return actions
    }

    static func canMatch(_ item: MediaItem) -> Bool {
        [.movie, .series].contains(item.type)
    }

    func artworkPicker(for item: MediaItem) -> ArtworkPickerViewModel? {
        guard manageActions(for: item).contains(.editArtwork) else { return nil }
        return management?.artworkPicker(item)
    }

    func matchSearch(for item: MediaItem) -> MatchSearchViewModel? {
        guard let management, management.canManageLibrary, Self.canMatch(item) else { return nil }
        return management.matchSearch(item)
    }

    func unmatch(_ item: MediaItem) async -> Outcome {
        guard let management, management.canManageLibrary, management.supportsUnmatch, Self.canMatch(item)
        else { return .cancelled }
        return await performManagement(on: item) { try await management.unmatch(item.id) }
    }

    func setPlayed(_ played: Bool, for item: MediaItem) async -> Outcome {
        await perform { try await setPlayedHandler(played, item.id) }
    }

    func setFavorite(_ favorite: Bool, for item: MediaItem) async -> Outcome {
        guard canFavorite(item) else { return .cancelled }
        return await perform { try await setFavoriteHandler(favorite, item) }
    }

    func removeFromContinueWatching(_ item: MediaItem) async -> Outcome {
        guard let removeFromContinueWatchingHandler else { return .cancelled }
        return await perform { try await removeFromContinueWatchingHandler(item.id) }
    }

    func refreshMetadata(_ item: MediaItem) async -> Outcome {
        guard let management, management.canManageLibrary else { return .cancelled }
        return await performManagement(on: item) { try await management.refreshMetadata(item.id) }
    }

    func analyze(_ item: MediaItem) async -> Outcome {
        guard let management, management.canManageLibrary, management.supportsAnalyze else { return .cancelled }
        return await performManagement(on: item) { try await management.analyze(item.id) }
    }

    /// Checks the user may delete this item and tells what it removes, for the confirmation.
    func prepareDeletion(of item: MediaItem) async -> DeletionPreparation {
        guard let management, manageActions(for: item).contains(.delete) else { return .cancelled }
        do {
            let impact = try await management.deletionImpact(item)
            return Task.isCancelled ? .cancelled : .ready(impact)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .cancelled }
            return .failed(message: deletionFailureMessage(for: error))
        }
    }

    func delete(_ item: MediaItem) async -> Outcome {
        guard let management, manageActions(for: item).contains(.delete) else { return .cancelled }
        do {
            do {
                try await management.delete(item)
            } catch where error.isNotFound {
                // Already deleted elsewhere since the confirmation opened, which is the outcome asked for.
            }
            // The item is gone even if the task was cancelled meanwhile.
            management.deleted(item.id)
            return .succeeded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .cancelled }
            return .failed(message: deletionFailureMessage(for: error))
        }
    }

    private func deletionFailureMessage(for error: Error) -> String {
        guard error.isManagementRefusal else {
            ErrorReporter.capture(error)
            return error.localizedDescription
        }
        // Plex refuses every deletion while its "Allow media deletion" setting is off.
        return error is PlexAPIError
            ? String(localized: "media.manage.delete.error.plexDisabled")
            : String(localized: "media.manage.delete.error.forbidden")
    }

    private func performManagement(on item: MediaItem, _ operation: () async throws -> Void) async -> Outcome {
        do {
            try await operation()
            management?.updateStarted(item.id)
            return Task.isCancelled ? .cancelled : .succeeded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .cancelled }
            // A refusal is the server's answer to a right lost meanwhile, not a bug.
            guard !error.isManagementRefusal else {
                return .failed(message: String(localized: "media.manage.error.forbidden"))
            }
            ErrorReporter.capture(error)
            return .failed(message: error.localizedDescription)
        }
    }

    private func perform(_ operation: () async throws -> Void) async -> Outcome {
        do {
            try await operation()
            // The server applied the change even if the task was cancelled meanwhile.
            didChange()
            return Task.isCancelled ? .cancelled : .succeeded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .cancelled }
            ErrorReporter.capture(error)
            return .failed(message: error.localizedDescription)
        }
    }
}

extension Error {
    var isManagementRefusal: Bool {
        if case let .requestFailed(statusCode)? = self as? PlexAPIError {
            return statusCode == 403
        }
        return (self as? JellyfinAPIError) == .permissionDenied
    }
}
