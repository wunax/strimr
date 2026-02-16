import Foundation

@MainActor
final class SharePlayPlaybackSyncEngine {
    private let sendMessage: (SharePlayPlaybackMessage) -> Void
    private let showToast: (String) -> Void

    private var seenEventIds: Set<UUID> = []
    private var suppressOutboundEvents = false
    private var isEnabled = false
    private weak var playerCoordinator: (any PlayerCoordinating)?

    init(
        sendMessage: @escaping (SharePlayPlaybackMessage) -> Void,
        showToast: @escaping (String) -> Void
    ) {
        self.sendMessage = sendMessage
        self.showToast = showToast
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            seenEventIds.removeAll()
        }
    }

    func attachCoordinator(_ coordinator: any PlayerCoordinating) {
        playerCoordinator = coordinator
    }

    func detachCoordinator() {
        playerCoordinator = nil
    }

    // MARK: - Outbound

    func emitPlayPause(isCurrentlyPaused: Bool) {
        guard isEnabled, !suppressOutboundEvents else { return }
        let type: SharePlayPlaybackMessage.EventType = isCurrentlyPaused ? .play : .pause
        let message = SharePlayPlaybackMessage(type: type)
        sendMessage(message)
    }

    func emitSeek(to positionSeconds: Double) {
        guard isEnabled, !suppressOutboundEvents else { return }
        let message = SharePlayPlaybackMessage(
            type: .seek,
            positionSeconds: positionSeconds
        )
        sendMessage(message)
    }

    func emitSetRate(_ rate: Float) {
        guard isEnabled, !suppressOutboundEvents else { return }
        let message = SharePlayPlaybackMessage(
            type: .setRate,
            rate: rate
        )
        sendMessage(message)
    }

    // MARK: - Inbound

    func handleRemoteMessage(_ message: SharePlayPlaybackMessage) {
        guard isEnabled else { return }
        guard let coordinator = playerCoordinator else { return }
        guard seenEventIds.insert(message.eventId).inserted else { return }

        suppressOutboundEvents = true
        defer { suppressOutboundEvents = false }

        switch message.type {
        case .play:
            coordinator.resume()
            showToast(String(localized: "sharePlay.toast.played"))
        case .pause:
            coordinator.pause()
            showToast(String(localized: "sharePlay.toast.paused"))
        case .seek:
            if let positionSeconds = message.positionSeconds {
                coordinator.seek(to: positionSeconds)
                showToast(String(localized: "sharePlay.toast.seeked"))
            }
        case .setRate:
            if let rate = message.rate {
                coordinator.setPlaybackRate(rate)
                showToast(String(localized: "sharePlay.toast.rate"))
            }
        }
    }
}
