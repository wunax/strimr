import Foundation

enum MediaQuickAction: Hashable {
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

    var title: String {
        switch self {
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
        }
    }

    var systemImage: String {
        switch self {
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

    private let supportsFavorites: Bool
    private let setPlayedHandler: (Bool, String) async throws -> Void
    private let setFavoriteHandler: (Bool, MediaItem) async throws -> Void

    init(services: MediaServices) {
        supportsFavorites = services.capabilities.favorites
        setPlayedHandler = { played, itemID in try await services.detail.setPlayed(played, itemID: itemID) }
        setFavoriteHandler = { favorite, media in try await services.favorites.setFavorite(favorite, media: media) }
    }

    init(
        supportsFavorites: Bool,
        setPlayed: @escaping (Bool, String) async throws -> Void,
        setFavorite: @escaping (Bool, MediaItem) async throws -> Void,
    ) {
        self.supportsFavorites = supportsFavorites
        setPlayedHandler = setPlayed
        setFavoriteHandler = setFavorite
    }

    func canFavorite(_ item: MediaItem) -> Bool {
        supportsFavorites && [.movie, .series, .season, .episode].contains(item.type)
    }

    /// Series and seasons have no play entry: what to play first is only known once the detail page has loaded.
    func menuActions(
        for item: MediaItem,
        canDownload: Bool,
        canAddToPlaylist: Bool = false,
    ) -> [MediaQuickAction] {
        var actions: [MediaQuickAction] = []
        if [.movie, .episode, .clip].contains(item.type) {
            let hasProgress = (item.viewOffset ?? 0) > 0
            actions.append(hasProgress ? .resume : .play)
            if hasProgress {
                actions.append(.playFromStart)
            }
        }
        if [.movie, .series, .season, .episode].contains(item.type) {
            actions.append(item.isFullyWatched ? .markUnwatched : .markWatched)
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
        return actions
    }

    func setPlayed(_ played: Bool, for item: MediaItem) async -> Outcome {
        await perform { try await setPlayedHandler(played, item.id) }
    }

    func setFavorite(_ favorite: Bool, for item: MediaItem) async -> Outcome {
        guard canFavorite(item) else { return .cancelled }
        return await perform { try await setFavoriteHandler(favorite, item) }
    }

    private func perform(_ operation: () async throws -> Void) async -> Outcome {
        do {
            try await operation()
            return Task.isCancelled ? .cancelled : .succeeded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .cancelled }
            ErrorReporter.capture(error)
            return .failed(message: error.localizedDescription)
        }
    }
}
