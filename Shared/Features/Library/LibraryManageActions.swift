import Foundation

enum LibraryManageAction: Hashable {
    case scan
    case refreshMetadata
    case analyze
    case emptyTrash

    var title: String {
        switch self {
        case .scan: String(localized: "library.manage.scan")
        case .refreshMetadata: String(localized: "library.manage.refreshMetadata")
        case .analyze: String(localized: "library.manage.analyze")
        case .emptyTrash: String(localized: "library.manage.emptyTrash")
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "arrow.triangle.2.circlepath"
        case .refreshMetadata: "arrow.clockwise"
        case .analyze: "waveform.badge.magnifyingglass"
        case .emptyTrash: "trash"
        }
    }

    func confirmationMessage(for library: Library) -> String {
        switch self {
        case .scan: String(localized: "library.manage.scan.confirmation \(library.title)")
        case .refreshMetadata: String(localized: "library.manage.refreshMetadata.confirmation \(library.title)")
        case .analyze: String(localized: "library.manage.analyze.confirmation \(library.title)")
        case .emptyTrash: String(localized: "library.manage.emptyTrash.confirmation \(library.title)")
        }
    }

    var startedTitle: String {
        switch self {
        case .scan: String(localized: "library.manage.scan.started")
        case .refreshMetadata: String(localized: "media.manage.refreshMetadata.started")
        case .analyze: String(localized: "media.manage.analyze.started")
        case .emptyTrash: String(localized: "library.manage.emptyTrash.started")
        }
    }

    var startedMessage: String {
        switch self {
        case .scan: String(localized: "library.manage.scan.startedMessage")
        case .refreshMetadata: String(localized: "media.manage.refreshMetadata.startedMessage")
        case .analyze: String(localized: "media.manage.analyze.startedMessage")
        case .emptyTrash: String(localized: "library.manage.emptyTrash.startedMessage")
        }
    }

    var failureTitle: String {
        switch self {
        case .scan: String(localized: "library.manage.scan.error")
        case .refreshMetadata: String(localized: "media.manage.refreshMetadata.error")
        case .analyze: String(localized: "media.manage.analyze.error")
        case .emptyTrash: String(localized: "library.manage.emptyTrash.error")
        }
    }
}

/// The server administration actions of a library, offered only to the users who manage it.
@MainActor
struct LibraryManageActions {
    struct Management {
        var supportsAnalyze: Bool
        var supportsTrash: Bool
        var perform: (LibraryManageAction, String) async throws -> Void
        /// The server applies the action in the background, after the call returns.
        var updateStarted: (String) -> Void = { _ in }
    }

    private let management: Management?

    /// Nothing is offered while the server is unreachable.
    init(services: MediaServices, isReachable: Bool) {
        let service = services.management
        management = services.authorization.canManageLibrary && isReachable
            ? Management(
                supportsAnalyze: service.supportsAnalyze,
                supportsTrash: service.supportsLibraryTrash,
                perform: { action, id in
                    switch action {
                    case .scan: try await service.scanLibrary(id: id)
                    case .refreshMetadata: try await service.refreshLibraryMetadata(id: id)
                    case .analyze: try await service.analyzeLibrary(id: id)
                    case .emptyTrash: try await service.emptyLibraryTrash(id: id)
                    }
                },
                updateStarted: { services.noteMediaChangeScheduled(itemID: $0) },
            )
            : nil
    }

    init(management: Management?) {
        self.management = management
    }

    /// Empty when the user does not manage the server, or for libraries that are not server sections.
    func actions(for library: Library) -> [LibraryManageAction] {
        guard let management, serverID(of: library) != nil else { return [] }
        var actions: [LibraryManageAction] = [.scan, .refreshMetadata]
        if management.supportsAnalyze {
            actions.append(.analyze)
        }
        if management.supportsTrash {
            actions.append(.emptyTrash)
        }
        return actions
    }

    func perform(_ action: LibraryManageAction, on library: Library) async -> MediaQuickActions.Outcome {
        guard let management, actions(for: library).contains(action), let id = serverID(of: library) else {
            return .cancelled
        }
        do {
            try await management.perform(action, id)
            management.updateStarted(library.id)
            return Task.isCancelled ? .cancelled : .succeeded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return .cancelled }
            guard !error.isManagementRefusal else {
                return .failed(message: String(localized: "media.manage.error.forbidden"))
            }
            ErrorReporter.capture(error)
            return .failed(message: error.localizedDescription)
        }
    }

    /// Plex shared items and Jellyfin collection or playlist views are not libraries the server scans.
    private func serverID(of library: Library) -> String? {
        guard !library.isShared, [.movie, .series].contains(library.type) else { return nil }
        return switch library.server.provider {
        case .plex: library.sectionId.map(String.init)
        case .jellyfin: library.id
        }
    }
}
