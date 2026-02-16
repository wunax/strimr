import Foundation
import GroupActivities
import Observation

@MainActor
@Observable
final class SharePlayViewModel {
    enum SessionState {
        case idle
        case waitingForSession
        case joined(participantCount: Int)
    }

    var sessionState: SessionState = .idle
    var toasts: [ToastMessage] = []
    var sessionEndedSignal: UUID?

    @ObservationIgnored private var groupSession: GroupSession<StrimrSharePlayActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var messageReceiveTask: Task<Void, Never>?
    @ObservationIgnored private var stateObservationTask: Task<Void, Never>?
    @ObservationIgnored private var participantObservationTask: Task<Void, Never>?
    @ObservationIgnored private var playbackLauncher: PlaybackLauncher?
    @ObservationIgnored private let context: PlexAPIContext

    @ObservationIgnored private lazy var playbackSyncEngine: SharePlayPlaybackSyncEngine = .init(
        sendMessage: { [weak self] message in
            Task { await self?.sendPlaybackMessage(message) }
        },
        showToast: { [weak self] message in
            self?.showToast(message)
        }
    )

    var isInSession: Bool {
        if case .joined = sessionState { return true }
        return false
    }

    init(context: PlexAPIContext) {
        self.context = context
    }

    func configurePlaybackLauncher(_ launcher: PlaybackLauncher) {
        playbackLauncher = launcher
    }

    // MARK: - Start / Observe

    func startSharePlay(
        ratingKey: String,
        type: PlexItemType,
        title: String,
        thumbPath: String?
    ) {
        let activity = StrimrSharePlayActivity(
            ratingKey: ratingKey,
            type: type,
            title: title,
            thumbPath: thumbPath
        )
        Task {
            do {
                _ = try await activity.activate()
                sessionState = .waitingForSession
            } catch {
                showToast(String(localized: "sharePlay.error.activate"))
            }
        }
    }

    func observeSessions() {
        sessionTask = Task {
            for await session in StrimrSharePlayActivity.sessions() {
                await configureSession(session)
            }
        }
    }

    // MARK: - Session Configuration

    private func configureSession(_ session: GroupSession<StrimrSharePlayActivity>) async {
        teardownSession()

        groupSession = session
        let activity = session.activity

        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        stateObservationTask = Task { [weak self] in
            for await state in session.$state.values {
                await MainActor.run {
                    self?.handleSessionStateChange(state)
                }
            }
        }

        participantObservationTask = Task { [weak self] in
            for await participants in session.$activeParticipants.values {
                await MainActor.run {
                    self?.sessionState = .joined(participantCount: participants.count)
                }
            }
        }

        messageReceiveTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: SharePlayPlaybackMessage.self) {
                await MainActor.run {
                    self?.playbackSyncEngine.handleRemoteMessage(message)
                }
            }
        }

        session.join()
        sessionState = .joined(participantCount: session.activeParticipants.count)

        await verifyAndStartPlayback(
            ratingKey: activity.ratingKey,
            type: activity.type
        )
    }

    private func handleSessionStateChange(_ state: GroupSession<StrimrSharePlayActivity>.State) {
        switch state {
        case .waiting, .joined:
            break
        case .invalidated:
            showToast(String(localized: "sharePlay.toast.ended"))
            teardownSession()
            sessionEndedSignal = UUID()
        @unknown default:
            break
        }
    }

    // MARK: - Playback

    private func verifyAndStartPlayback(ratingKey: String, type: PlexItemType) async {
        do {
            let repository = try MetadataRepository(context: context)
            let container = try await repository.getMetadata(
                ratingKey: ratingKey,
                params: MetadataRepository.PlexMetadataParams(checkFiles: true)
            )
            guard !(container.mediaContainer.metadata?.isEmpty ?? true) else {
                showToast(String(localized: "sharePlay.error.noAccess"))
                leaveSession()
                return
            }
        } catch {
            showToast(String(localized: "sharePlay.error.noAccess"))
            leaveSession()
            return
        }

        guard let playbackLauncher else {
            showToast(String(localized: "sharePlay.error.playbackLauncher"))
            return
        }

        await playbackLauncher.play(
            ratingKey: ratingKey,
            type: type,
            shouldResumeFromOffset: false
        )
    }

    // MARK: - Player Coordinator

    func attachPlayerCoordinator(_ coordinator: any PlayerCoordinating) {
        playbackSyncEngine.attachCoordinator(coordinator)
        playbackSyncEngine.setEnabled(true)
    }

    func detachPlayerCoordinator() {
        playbackSyncEngine.setEnabled(false)
        playbackSyncEngine.detachCoordinator()
    }

    // MARK: - Outbound Sync

    func sendPlayPause(isCurrentlyPaused: Bool) {
        playbackSyncEngine.emitPlayPause(isCurrentlyPaused: isCurrentlyPaused)
    }

    func sendSeek(to positionSeconds: Double) {
        playbackSyncEngine.emitSeek(to: positionSeconds)
    }

    func sendRateChange(_ rate: Float) {
        playbackSyncEngine.emitSetRate(rate)
    }

    // MARK: - Leave / Teardown

    func leaveSession() {
        groupSession?.leave()
        teardownSession()
    }

    func endSessionForAll() {
        groupSession?.end()
        teardownSession()
    }

    private func teardownSession() {
        messageReceiveTask?.cancel()
        stateObservationTask?.cancel()
        participantObservationTask?.cancel()
        playbackSyncEngine.setEnabled(false)
        groupSession = nil
        messenger = nil
        sessionState = .idle
    }

    // MARK: - Messaging

    private func sendPlaybackMessage(_ message: SharePlayPlaybackMessage) async {
        guard let messenger else { return }
        do {
            try await messenger.send(message)
        } catch {
            showToast(String(localized: "sharePlay.error.send"))
        }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        let toast = ToastMessage(title: message)
        toasts.append(toast)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self?.toasts.removeAll { $0.id == toast.id }
            }
        }
    }
}
