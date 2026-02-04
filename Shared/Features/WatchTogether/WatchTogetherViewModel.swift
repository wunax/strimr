import Foundation
import Observation

@MainActor
@Observable
final class WatchTogetherViewModel {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    enum Role {
        case none
        case host
        case guest
    }

    var connectionState: ConnectionState = .disconnected
    var role: Role = .none
    var code: String = ""
    var joinCode: String = ""
    var participants: [WatchTogetherParticipant] = []
    var selectedMedia: WatchTogetherSelectedMedia?
    var readyMap: [String: Bool] = [:]
    var mediaAccessMap: [String: Bool] = [:]
    var errorMessage: String?
    var toasts: [ToastMessage] = []
    var isSessionStarted = false
    var sessionEndedSignal: UUID?
    var playbackStoppedSignal: UUID?
    var participantId: String?

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let client = WatchTogetherWebSocketClient()
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var playbackLauncher: PlaybackLauncher?
    @ObservationIgnored private var lastMediaAccessRatingKey: String?
    @ObservationIgnored private lazy var playbackSyncEngine: WatchTogetherPlaybackSyncEngine = {
        WatchTogetherPlaybackSyncEngine(
            sendEvent: { [weak self] event in
                Task { await self?.sendPlayerEvent(event) }
            },
            showToast: { [weak self] message in
                self?.showToast(message)
            },
            currentParticipantId: { [weak self] in
                self?.currentParticipantId
            },
        )
    }()

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        self.context = context

        client.onMessage = { [weak self] message in
            self?.handle(message)
        }

        client.onDisconnect = { [weak self] error in
            self?.handleDisconnect(error)
        }
    }

    var isInSession: Bool {
        !code.isEmpty && role != .none
    }

    var isHost: Bool {
        role == .host
    }

    var currentUserId: String? {
        sessionManager.user?.uuid
    }

    var currentParticipantId: String? {
        participantId ?? currentUserId
    }

    var currentDisplayName: String? {
        sessionManager.user?.friendlyName
            ?? sessionManager.user?.title
            ?? sessionManager.user?.username
    }

    var plexServerId: String? {
        sessionManager.plexServer?.clientIdentifier
    }

    var canStartPlayback: Bool {
        guard isHost, selectedMedia != nil else { return false }
        guard !participants.isEmpty else { return false }
        return participants.allSatisfy { $0.isReady && $0.hasMediaAccess }
    }

    func configurePlaybackLauncher(_ launcher: PlaybackLauncher) {
        playbackLauncher = launcher
    }

    func createSession() {
        guard let identity = makeIdentityPayload() else { return }
        client.disconnect()
        resetSessionState(clearJoinCode: false)
        role = .host
        connectAndSend(.createSession(identity))
    }

    func joinSession() {
        let trimmed = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            showToast(String(localized: "watchTogether.error.missingCode"))
            return
        }

        guard let identity = makeIdentityPayload(code: trimmed) else { return }
        joinCode = trimmed
        client.disconnect()
        resetSessionState(clearJoinCode: false)
        role = .guest
        connectAndSend(.joinSession(identity))
    }

    func leaveSession(endForAll: Bool) {
        Task {
            await sendMessage(.leaveSession(LeaveSessionRequest(endForAll: endForAll)))
            client.disconnect()
            resetSessionState(clearJoinCode: false)
        }
    }

    func toggleReady() {
        guard let participantId = currentParticipantId else { return }
        let isReady = !(readyMap[participantId] ?? false)
        Task {
            await sendMessage(.setReady(SetReadyRequest(isReady: isReady)))
        }
    }

    func setSelectedMedia(_ media: MediaDisplayItem) {
        guard isHost else { return }
        Task {
            let selected = WatchTogetherSelectedMedia(media: media)
            let hasAccess = await verifyMediaAccess(for: selected)
            guard hasAccess else {
                showToast(String(localized: "watchTogether.error.mediaUnavailable"))
                return
            }

            selectedMedia = selected
            isSessionStarted = false
            playbackSyncEngine.setEnabled(false)
            await sendMessage(.setSelectedMedia(SetSelectedMediaRequest(media: selected)))
            await sendMessage(.mediaAccess(MediaAccessRequest(hasAccess: true)))
        }
    }

    func startPlayback() {
        guard isHost else { return }
        guard let selectedMedia else { return }
        Task {
            await sendMessage(
                .startPlayback(
                    StartPlaybackRequest(
                        ratingKey: selectedMedia.ratingKey,
                        type: selectedMedia.type,
                    )
                )
            )
        }
    }

    func stopPlaybackForEveryone() {
        guard isHost else { return }
        Task {
            await sendMessage(.stopPlayback(StopPlaybackRequest(reason: nil)))
        }
    }

    func attachPlayerCoordinator(_ coordinator: any PlayerCoordinating) {
        playbackSyncEngine.attachCoordinator(coordinator)
    }

    func detachPlayerCoordinator() {
        playbackSyncEngine.detachCoordinator()
    }

    func sendPlayPause(isCurrentlyPaused: Bool) {
        playbackSyncEngine.emitPlayPause(isCurrentlyPaused: isCurrentlyPaused)
    }

    func sendSeek(to positionSeconds: Double) {
        playbackSyncEngine.emitSeek(to: positionSeconds)
    }

    func sendRateChange(_ rate: Float) {
        playbackSyncEngine.emitSetRate(rate)
    }

    private func connectAndSend(_ message: WatchTogetherClientMessage) {
        Task {
            do {
                connectionState = .connecting
                try await client.connect()
                connectionState = .connected
                await sendMessage(message)
            } catch {
                connectionState = .disconnected
                showToast(String(localized: "watchTogether.error.connection"))
            }
        }
    }

    private func sendMessage(_ message: WatchTogetherClientMessage) async {
        do {
            try await client.send(message)
        } catch {
            showToast(String(localized: "watchTogether.error.send"))
        }
    }

    private func sendPlayerEvent(_ event: WatchTogetherPlayerEvent) async {
        await sendMessage(.playerEvent(PlayerEventRequest(event: event)))
    }

    private func handle(_ message: WatchTogetherServerMessage) {
        switch message {
        case let .created(payload):
            code = payload.code
            participantId = payload.participantId
            role = payload.hostId == payload.participantId ? .host : .guest
            showToast(String(localized: "watchTogether.toast.created \(payload.code)"))
        case let .joined(payload):
            code = payload.code
            participantId = payload.participantId
            role = payload.hostId == payload.participantId ? .host : .guest
            showToast(String(localized: "watchTogether.toast.joined \(payload.code)"))
        case let .lobbySnapshot(snapshot):
            apply(snapshot: snapshot)
        case let .participantUpdate(payload):
            updateParticipant(payload.participant)
        case let .sessionEnded(payload):
            handleSessionEnded(reason: payload.reason)
        case let .error(payload):
            errorMessage = payload.message
            showToast(payload.message)
        case .pong:
            break
        case let .startPlayback(payload):
            handleStartPlayback(payload)
        case let .playbackStopped(payload):
            handlePlaybackStopped(payload)
        case let .playerEvent(event):
            let senderName = participants.first(where: { $0.id == event.senderId })?.displayName
            playbackSyncEngine.handleRemoteEvent(event, senderName: senderName)
        }
    }

    private func handleDisconnect(_ error: Error?) {
        guard isInSession else {
            connectionState = .disconnected
            return
        }

        connectionState = .reconnecting
        showToast(String(localized: "watchTogether.toast.reconnecting"))
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0

            while isInSession {
                let delay = min(16.0, pow(2.0, Double(attempt)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                do {
                    try await client.connect()
                    connectionState = .connected
                    let targetCode = code.isEmpty ? joinCode : code
                    if !targetCode.isEmpty, let identity = makeIdentityPayload(code: targetCode) {
                        await sendMessage(.joinSession(identity))
                    }
                    return
                } catch {
                    attempt += 1
                }
            }
        }
    }

    private func apply(snapshot: WatchTogetherLobbySnapshot) {
        code = snapshot.code
        role = snapshot.hostId == currentParticipantId ? .host : .guest
        participants = snapshot.participants
        selectedMedia = snapshot.selectedMedia
        isSessionStarted = snapshot.started
        playbackSyncEngine.setEnabled(snapshot.started)

        readyMap = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.isReady) })
        mediaAccessMap = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0.hasMediaAccess) })

        handleSelectedMediaChange(snapshot.selectedMedia)
    }

    private func handleSelectedMediaChange(_ media: WatchTogetherSelectedMedia?) {
        guard let media else {
            lastMediaAccessRatingKey = nil
            return
        }

        guard media.ratingKey != lastMediaAccessRatingKey else { return }
        lastMediaAccessRatingKey = media.ratingKey

        Task {
            let hasAccess = await verifyMediaAccess(for: media)
            await sendMessage(.mediaAccess(MediaAccessRequest(hasAccess: hasAccess)))
            if !hasAccess {
                showToast(String(localized: "watchTogether.toast.noAccess"))
            }
        }
    }

    private func updateParticipant(_ participant: WatchTogetherParticipant) {
        if let index = participants.firstIndex(where: { $0.id == participant.id }) {
            participants[index] = participant
        } else {
            participants.append(participant)
        }

        readyMap[participant.id] = participant.isReady
        mediaAccessMap[participant.id] = participant.hasMediaAccess
    }

    private func handleSessionEnded(reason: String?) {
        if let reason {
            showToast(reason)
        } else {
            showToast(String(localized: "watchTogether.toast.ended"))
        }

        sessionEndedSignal = UUID()
        client.disconnect()
        resetSessionState(clearJoinCode: false)
    }

    private func handlePlaybackStopped(_ payload: PlaybackStopped) {
        isSessionStarted = false
        playbackSyncEngine.setEnabled(false)
        playbackStoppedSignal = UUID()
        if let reason = payload.reason {
            showToast(reason)
        }
    }

    private func resetSessionState(clearJoinCode: Bool) {
        reconnectTask?.cancel()
        connectionState = .disconnected
        role = .none
        code = ""
        if clearJoinCode {
            joinCode = ""
        }
        participants = []
        selectedMedia = nil
        readyMap = [:]
        mediaAccessMap = [:]
        errorMessage = nil
        isSessionStarted = false
        participantId = nil
        playbackSyncEngine.setEnabled(false)
        lastMediaAccessRatingKey = nil
    }

    private func verifyMediaAccess(for media: WatchTogetherSelectedMedia) async -> Bool {
        do {
            let repository = try MetadataRepository(context: context)
            let container = try await repository.getMetadata(
                ratingKey: media.ratingKey,
                params: MetadataRepository.PlexMetadataParams(checkFiles: true),
            )
            return !(container.mediaContainer.metadata?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    private func handleStartPlayback(_ payload: WatchTogetherStartPlayback) {
        isSessionStarted = true
        playbackSyncEngine.setEnabled(true)

        Task {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let delayMs = max(0, payload.startAtEpochMs - nowMs)
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }

            guard let playbackLauncher else {
                showToast(String(localized: "watchTogether.error.playbackLauncher"))
                return
            }

            await playbackLauncher.play(
                ratingKey: payload.ratingKey,
                type: payload.type,
                shouldResumeFromOffset: false,
            )
        }
    }

    private func makeIdentityPayload() -> CreateSessionRequest? {
        guard let plexServerId, let participantId = currentUserId, let displayName = currentDisplayName else {
            showToast(String(localized: "watchTogether.error.identity"))
            return nil
        }

        return CreateSessionRequest(
            plexServerId: plexServerId,
            participantId: participantId,
            displayName: displayName,
        )
    }

    private func makeIdentityPayload(code: String) -> JoinSessionRequest? {
        guard let plexServerId, let participantId = currentUserId, let displayName = currentDisplayName else {
            showToast(String(localized: "watchTogether.error.identity"))
            return nil
        }

        return JoinSessionRequest(
            code: code,
            plexServerId: plexServerId,
            participantId: participantId,
            displayName: displayName,
        )
    }

    private func showToast(_ message: String) {
        let toast = ToastMessage(title: message)
        toasts.append(toast)
        scheduleToastRemoval(id: toast.id)
    }

    private func scheduleToastRemoval(id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self?.toasts.removeAll { $0.id == id }
            }
        }
    }
}
