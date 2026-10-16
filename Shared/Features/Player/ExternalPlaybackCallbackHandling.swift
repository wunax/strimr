import Foundation
import Observation
import SwiftUI

@Observable
final class ExternalPlaybackCallbackRouter {
    private(set) var pending: ExternalPlaybackCallback?

    /// Whether the URL was an external player callback.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let callback = ExternalPlaybackCallback(url: url) else { return false }
        pending = callback
        return true
    }

    func clear(_ callback: ExternalPlaybackCallback) {
        guard pending == callback else { return }
        pending = nil
    }
}

enum ExternalPlaybackProgressUpdate: Equatable {
    case watched
    case position(TimeInterval, duration: TimeInterval?)
}

extension ExternalPlaybackCallback {
    /// Same as the downloaded playback threshold, which tvOS does not build.
    private static let watchedThreshold = 0.9

    var progressUpdate: ExternalPlaybackProgressUpdate? {
        guard case let .finished(position, progress) = outcome, let position else { return nil }
        let duration = duration ?? progress.flatMap { $0 > 0 ? position / $0 : nil }
        let fraction = progress ?? duration.flatMap { $0 > 0 ? position / $0 : nil }
        if let fraction, fraction >= Self.watchedThreshold {
            return .watched
        }
        // A player closed before reporting any progress must not reset the resume point.
        guard position > 0 else { return nil }
        return .position(position, duration: duration)
    }
}

private struct ExternalPlaybackCallbackHandling: ViewModifier {
    @Environment(ExternalPlaybackCallbackRouter.self) private var router
    @Environment(ServerRegistry.self) private var registry
    @State private var isShowingFailure = false
    @State private var failureMessage: String?
    let onFinish: (ServerIdentity) -> Void

    private struct TaskID: Equatable {
        let callback: ExternalPlaybackCallback?
        let readyServers: Set<ServerIdentity>
    }

    func body(content: Content) -> some View {
        content
            // After a cold launch the callback can arrive before its server is ready, so it waits for it.
            .task(id: TaskID(callback: router.pending, readyServers: registry.readyServers)) {
                guard let callback = router.pending else { return }
                await handle(callback)
            }
            .alert("player.external.playbackFailed", isPresented: $isShowingFailure) {
                Button("common.actions.done") {}
            } message: {
                if let failureMessage {
                    Text(failureMessage)
                }
            }
    }

    private func handle(_ callback: ExternalPlaybackCallback) async {
        if case let .failed(message) = callback.outcome {
            router.clear(callback)
            failureMessage = message
            isShowingFailure = true
            return
        }
        guard let item = callback.item else {
            router.clear(callback)
            return
        }
        guard let services = registry.services(for: item.server) else { return }
        if let update = callback.progressUpdate {
            do {
                switch update {
                case .watched:
                    try await services.playback.markItemWatched(itemID: item.itemID, at: Date())
                case let .position(position, duration):
                    try await services.playback.pushItemPosition(
                        itemID: item.itemID,
                        position: position,
                        duration: duration,
                        at: Date(),
                    )
                }
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
        // Cleared only once done: clearing changes the task id, which cancels the task.
        router.clear(callback)
        onFinish(item.server)
    }
}

extension View {
    /// Syncs the progress reported by an external player when it calls back, then hands over the server to refresh.
    func handlesExternalPlaybackCallbacks(onFinish: @escaping (ServerIdentity) -> Void) -> some View {
        modifier(ExternalPlaybackCallbackHandling(onFinish: onFinish))
    }
}
