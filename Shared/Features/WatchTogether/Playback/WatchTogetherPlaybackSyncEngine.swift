import Foundation

@MainActor
final class WatchTogetherPlaybackSyncEngine {
    private let sendEvent: (WatchTogetherPlayerEvent) -> Void
    private let showToast: (String) -> Void
    private let currentParticipantId: () -> String?

    private var seenEventIds: Set<UUID> = []
    private var suppressOutboundEvents = false
    private var isEnabled = false
    private weak var playerCoordinator: (any PlayerCoordinating)?

    init(
        sendEvent: @escaping (WatchTogetherPlayerEvent) -> Void,
        showToast: @escaping (String) -> Void,
        currentParticipantId: @escaping () -> String?,
    ) {
        self.sendEvent = sendEvent
        self.showToast = showToast
        self.currentParticipantId = currentParticipantId
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

    func emitPlayPause(isCurrentlyPaused: Bool) {
        guard isEnabled, !suppressOutboundEvents else { return }
        guard let senderId = currentParticipantId() else { return }
        let type: WatchTogetherPlayerEvent.EventType = isCurrentlyPaused ? .play : .pause
        let event = WatchTogetherPlayerEvent(
            senderId: senderId,
            type: type,
            clientSentAtMs: Self.nowMs,
        )
        sendEvent(event)
    }

    func emitSeek(to positionSeconds: Double) {
        guard isEnabled, !suppressOutboundEvents else { return }
        guard let senderId = currentParticipantId() else { return }
        let event = WatchTogetherPlayerEvent(
            senderId: senderId,
            type: .seek,
            positionSeconds: positionSeconds,
            clientSentAtMs: Self.nowMs,
        )
        sendEvent(event)
    }

    func emitSetRate(_ rate: Float) {
        guard isEnabled, !suppressOutboundEvents else { return }
        guard let senderId = currentParticipantId() else { return }
        let event = WatchTogetherPlayerEvent(
            senderId: senderId,
            type: .setRate,
            rate: rate,
            clientSentAtMs: Self.nowMs,
        )
        sendEvent(event)
    }

    func handleRemoteEvent(_ event: WatchTogetherPlayerEvent, senderName: String?) {
        guard isEnabled else { return }
        guard let coordinator = playerCoordinator else { return }
        guard seenEventIds.insert(event.id).inserted else { return }

        if let senderId = currentParticipantId(), senderId == event.senderId {
            return
        }

        suppressOutboundEvents = true
        defer { suppressOutboundEvents = false }

        switch event.type {
        case .play:
            coordinator.resume()
            if let senderName {
                showToast(String(localized: "watchTogether.toast.played \(senderName)"))
            }
        case .pause:
            coordinator.pause()
            if let senderName {
                showToast(String(localized: "watchTogether.toast.paused \(senderName)"))
            }
        case .seek:
            if let positionSeconds = event.positionSeconds {
                coordinator.seek(to: positionSeconds)
                if let senderName {
                    showToast(String(localized: "watchTogether.toast.seeked \(senderName)"))
                }
            }
        case .setRate:
            if let rate = event.rate {
                coordinator.setPlaybackRate(rate)
                if let senderName {
                    showToast(String(localized: "watchTogether.toast.rate \(senderName)"))
                }
            }
        }
    }

    private static var nowMs: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
