import Foundation
import Observation

@MainActor
@Observable
final class MediaDeletionViewModel {
    enum State: Equatable {
        case loading
        case ready(MediaDeletionImpact)
        /// The deletion cannot be offered, or the server refused it.
        case failed(message: String)
        case deleting(MediaDeletionImpact)
        case deleted
    }

    let item: MediaItem
    private(set) var state: State = .loading
    @ObservationIgnored private let quickActions: MediaQuickActions

    init(item: MediaItem, quickActions: MediaQuickActions) {
        self.item = item
        self.quickActions = quickActions
    }

    var canDelete: Bool {
        if case .ready = state {
            return true
        }
        return false
    }

    var impact: MediaDeletionImpact? {
        switch state {
        case let .ready(impact), let .deleting(impact): impact
        default: nil
        }
    }

    func load() async {
        switch await quickActions.prepareDeletion(of: item) {
        case let .ready(impact): state = .ready(impact)
        case let .failed(message): state = .failed(message: message)
        case .cancelled: break
        }
    }

    func delete() async {
        guard case let .ready(impact) = state else { return }
        state = .deleting(impact)
        switch await quickActions.delete(item) {
        case .succeeded: state = .deleted
        case let .failed(message): state = .failed(message: message)
        case .cancelled: state = .ready(impact)
        }
    }
}
