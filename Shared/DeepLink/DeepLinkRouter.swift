import Foundation
import Observation

/// Holds the one link waiting to be handled. A newer link replaces it.
@MainActor
@Observable
final class DeepLinkRouter {
    /// A search the Search tab runs once it shows.
    struct SearchRequest: Equatable {
        let id = UUID()
        let query: String
    }

    /// The router of the app, for entry points that live outside SwiftUI (scene delegate, dock menu, App Intents).
    static let shared = DeepLinkRouter()

    static let duplicateWindow: TimeInterval = 2

    private(set) var pending: DeepLink?
    var searchRequest: SearchRequest?
    /// The profile a link is waiting for while its PIN is typed in the picker.
    var awaitedProfileID: String?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastReceived: (link: DeepLink, date: Date)?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Whether the URL was a Strimr link. The same open can arrive twice, e.g. as a URL and as a user activity.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }
        receive(link)
        return true
    }

    func receive(_ link: DeepLink) {
        let date = now()
        if let lastReceived, lastReceived.link == link,
           date.timeIntervalSince(lastReceived.date) < Self.duplicateWindow
        {
            return
        }
        lastReceived = (link, date)
        awaitedProfileID = nil
        pending = link
    }

    /// Ignored when a newer link replaced this one meanwhile.
    func clear(_ link: DeepLink) {
        guard pending == link else { return }
        pending = nil
        awaitedProfileID = nil
    }

    /// Once the profile of a link is active, the link is handled as one without a profile.
    func resolveProfile(of link: DeepLink) {
        guard pending == link else { return }
        awaitedProfileID = nil
        pending = link.withProfile(nil)
    }
}
