import AVFoundation
import Combine
import Foundation
import GroupActivities
import Observation

@MainActor
@Observable
final class SharePlayCoordinator {
    private(set) var activity: StrimrWatchActivity?
    private(set) var isInSession = false
    private(set) var activityChangeID = UUID()
    private(set) var participantCount = 0
    private(set) var isActivating = false
    var errorMessage: String?

    var isEligibleForGroupSession: Bool {
        groupStateObserver.isEligibleForGroupSession
    }

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let groupStateObserver = GroupStateObserver()
    @ObservationIgnored private var session: GroupSession<StrimrWatchActivity>?
    @ObservationIgnored private var playbackLauncher: PlaybackLauncher?
    @ObservationIgnored private weak var playerController: PlayerController?
    @ObservationIgnored private var sessionSubscriptions: Set<AnyCancellable> = []
    @ObservationIgnored private var sessionListener: Task<Void, Never>?
    @ObservationIgnored private var locallyPreparedActivityIDs: Set<UUID> = []
    @ObservationIgnored private var pendingNextItem: MediaItem?
    @ObservationIgnored private var lastLaunchedActivityID: UUID?
    @ObservationIgnored private var sharingPresentationActivityID: UUID?
    @ObservationIgnored private var pendingSessionAcceptanceActivityID: UUID?
    @ObservationIgnored private var deferredSessionInvalidation = false
    @ObservationIgnored private var pendingInitialResumeActivityID: UUID?
    @ObservationIgnored private var lastCoordinatedActivityID: UUID?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        sessionListener = Task { [weak self] in
            for await session in StrimrWatchActivity.sessions() {
                guard !Task.isCancelled else { return }
                await self?.accept(session)
            }
        }
    }

    func configurePlaybackLauncher(_ launcher: PlaybackLauncher) {
        playbackLauncher = launcher
    }

    func makeActivity(
        ratingKey: String,
        type: MediaKind,
        title: String,
        initialPosition: Double,
        serverIdentifier: String? = nil,
    ) -> StrimrWatchActivity? {
        guard let services = sessionManager.mediaServices else {
            errorMessage = String(localized: "sharePlay.error.serverUnavailable")
            return nil
        }
        let serverIdentifier = serverIdentifier ?? services.identity.id
        return StrimrWatchActivity(
            activityID: UUID(),
            provider: services.provider,
            serverIdentifier: serverIdentifier,
            ratingKey: ratingKey,
            mediaKind: type,
            title: title,
            initialPosition: max(0, initialPosition),
        )
    }

    func activate(
        ratingKey: String,
        type: MediaKind,
        title: String,
        initialPosition: Double,
        serverIdentifier: String? = nil,
    ) async {
        guard !isActivating else { return }
        #if os(tvOS)
            guard groupStateObserver.isEligibleForGroupSession else {
                errorMessage = String(localized: "sharePlay.tv.guidance")
                return
            }
        #endif
        guard let activity = makeActivity(
            ratingKey: ratingKey,
            type: type,
            title: title,
            initialPosition: initialPosition,
            serverIdentifier: serverIdentifier,
        ) else { return }

        await activate(activity)
    }

    func activate(_ activity: StrimrWatchActivity) async {
        guard !isActivating else { return }

        isActivating = true
        locallyPreparedActivityIDs.insert(activity.activityID)
        defer { isActivating = false }

        if let session {
            session.activity = activity
            handleActivityChange(activity)
            if playerController == nil {
                await launchPlaybackIfNeeded(for: activity)
            }
            return
        }

        do {
            let preparationResult = await activity.prepareForActivation()
            switch preparationResult {
            case .activationPreferred:
                let activated = try await activity.activate()
                if !activated {
                    locallyPreparedActivityIDs.remove(activity.activityID)
                    errorMessage = String(localized: "sharePlay.error.unavailable")
                }
            case .activationDisabled:
                locallyPreparedActivityIDs.remove(activity.activityID)
                errorMessage = String(localized: "sharePlay.error.unavailable")
            case .cancelled:
                locallyPreparedActivityIDs.remove(activity.activityID)
            @unknown default:
                locallyPreparedActivityIDs.remove(activity.activityID)
                errorMessage = String(localized: "sharePlay.error.unavailable")
            }
        } catch {
            locallyPreparedActivityIDs.remove(activity.activityID)
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    func sharingDidStart(_ activity: StrimrWatchActivity) {
        locallyPreparedActivityIDs.insert(activity.activityID)
        sharingPresentationActivityID = activity.activityID
    }

    func sharingDidCancel(_ activity: StrimrWatchActivity) {
        locallyPreparedActivityIDs.remove(activity.activityID)
    }

    func sharingPresentationDidEnd() async {
        guard let activityID = sharingPresentationActivityID else { return }
        sharingPresentationActivityID = nil
        guard playerController == nil,
              let activity,
              activity.activityID == activityID
        else { return }
        await launchPlaybackIfNeeded(for: activity)
    }

    func attachPlayer(_ controller: PlayerController, ratingKey: String) {
        playerController = controller
        guard participantCount > 1,
              let session,
              let activity,
              activity.ratingKey == ratingKey
        else { return }
        controller.playbackCoordinator.coordinateWithSession(session)
        controller.beginCoordinatedPlayback(
            identifier: playbackIdentifier(for: activity),
            initialTime: activity.initialPosition,
        )
        lastCoordinatedActivityID = activity.activityID
    }

    func detachPlayer(_ controller: PlayerController) {
        guard playerController === controller else { return }
        playerController = nil
    }

    func playerDidLoad(ratingKey: String) {
        guard let activity, activity.ratingKey == ratingKey else { return }
        if participantCount > 1 {
            playerController?.reconcileCoordinatedPlaybackAfterLoad(
                identifier: playbackIdentifier(for: activity),
                initialTime: activity.initialPosition,
            )
        }
        if locallyPreparedActivityIDs.remove(activity.activityID) != nil {
            if participantCount > 1 {
                playerController?.resume()
            } else {
                pendingInitialResumeActivityID = activity.activityID
            }
        }
    }

    func updateToNextItem(_ item: MediaItem) {
        pendingNextItem = item
        publishPendingNextItemIfLeader()
    }

    private func publishPendingNextItemIfLeader() {
        guard let session, isLocalLeader, let item = pendingNextItem else { return }
        let next = StrimrWatchActivity(
            activityID: UUID(),
            provider: item.provider,
            serverIdentifier: session.activity.serverIdentifier,
            ratingKey: item.id,
            mediaKind: item.kind,
            title: item.title,
            initialPosition: 0,
        )
        locallyPreparedActivityIDs.insert(next.activityID)
        pendingNextItem = nil
        session.activity = next
    }

    func leave() {
        session?.leave()
        detach(continueLocally: false)
    }

    private var isLocalLeader: Bool {
        guard let session else { return false }
        let leader = session.activeParticipants.min {
            $0.id.uuidString < $1.id.uuidString
        }
        return leader?.id == session.localParticipant.id
    }

    private func accept(_ newSession: GroupSession<StrimrWatchActivity>) async {
        let acceptanceActivityID = newSession.activity.activityID
        pendingSessionAcceptanceActivityID = acceptanceActivityID
        do {
            try await ensureAccess(to: newSession.activity)
            guard pendingSessionAcceptanceActivityID == acceptanceActivityID else {
                newSession.leave()
                return
            }
        } catch {
            guard pendingSessionAcceptanceActivityID == acceptanceActivityID else {
                newSession.leave()
                return
            }
            pendingSessionAcceptanceActivityID = nil
            locallyPreparedActivityIDs.remove(newSession.activity.activityID)
            if Task.isCancelled || error.isCancellation {
                if deferredSessionInvalidation {
                    deferredSessionInvalidation = false
                    detach(continueLocally: true)
                }
                return
            }
            ErrorReporter.capture(error)
            errorMessage = String(localized: "sharePlay.error.mediaUnavailable")
            newSession.leave()
            if deferredSessionInvalidation {
                deferredSessionInvalidation = false
                detach(continueLocally: true)
            }
            return
        }

        let previousSession = session
        sessionSubscriptions.removeAll()
        if previousSession != nil,
           previousSession !== newSession,
           playerController?.isCoordinatedPlayback == true
        {
            playerController?.endCoordinatedPlayback(continueLocally: true)
        }
        previousSession?.leave()
        session = newSession
        handleActivityChange(newSession.activity)
        isInSession = true
        participantCount = newSession.activeParticipants.count
        pendingSessionAcceptanceActivityID = nil
        deferredSessionInvalidation = false

        newSession.$activity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity in self?.handleActivityChange(activity) }
            .store(in: &sessionSubscriptions)

        newSession.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                guard let self else { return }
                let previousCount = participantCount
                participantCount = participants.count
                handleParticipantCountChange(previousCount: previousCount)
                publishPendingNextItemIfLeader()
            }
            .store(in: &sessionSubscriptions)

        newSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard case .invalidated = state else { return }
                guard let self else { return }
                guard session === newSession else { return }
                if pendingSessionAcceptanceActivityID != nil {
                    deferredSessionInvalidation = true
                    return
                }
                detach(continueLocally: true)
            }
            .store(in: &sessionSubscriptions)

        newSession.join()
        if let playerController, let activity {
            if participantCount > 1 {
                playerController.playbackCoordinator.coordinateWithSession(newSession)
                playerController.beginCoordinatedPlayback(
                    identifier: playbackIdentifier(for: activity),
                    initialTime: activity.initialPosition,
                )
                lastCoordinatedActivityID = activity.activityID
            }
        } else if sharingPresentationActivityID != newSession.activity.activityID {
            await launchPlaybackIfNeeded(for: newSession.activity)
        }
    }

    private func launchPlaybackIfNeeded(for activity: StrimrWatchActivity) async {
        guard lastLaunchedActivityID != activity.activityID,
              let playbackLauncher
        else { return }
        lastLaunchedActivityID = activity.activityID
        do {
            let services = try await resolvedServices(for: activity)
            await playbackLauncher.using(services: services).play(
                ratingKey: activity.ratingKey,
                type: activity.mediaKind,
                shouldResumeFromOffset: false,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = String(localized: "sharePlay.error.mediaUnavailable")
        }
    }

    private func ensureAccess(to activity: StrimrWatchActivity) async throws {
        let services = try await resolvedServices(for: activity)
        _ = try await services.detail.mediaItem(id: activity.ratingKey)
    }

    func playerViewModel(for activity: StrimrWatchActivity) async throws -> PlayerViewModel {
        let services = try await resolvedServices(for: activity)
        let queue = try await services.playback.queue(
            startingWith: activity.ratingKey,
            kind: activity.mediaKind,
            shuffle: false,
        )
        guard !queue.items.isEmpty else { throw SharePlayError.mediaUnavailable }
        return PlayerViewModel(
            queue: queue,
            services: services,
            shouldResumeFromOffset: false,
        )
    }

    private func services(for activity: StrimrWatchActivity) -> MediaServices? {
        guard let services = sessionManager.mediaServices,
              services.provider == activity.provider,
              services.identity.id == activity.serverIdentifier
        else { return nil }
        return services
    }

    private func resolvedServices(for activity: StrimrWatchActivity) async throws -> MediaServices {
        if let services = services(for: activity) {
            return services
        }
        guard activity.provider == .plex else { throw SharePlayError.serverUnavailable }
        let context = try await sessionManager.serverContext(for: activity.serverIdentifier)
        guard let services = PlexMediaServicesFactory.make(context: context, sessionManager: sessionManager) else {
            throw SharePlayError.serverUnavailable
        }
        return services
    }

    private func handleActivityChange(_ newActivity: StrimrWatchActivity) {
        guard activity != newActivity else { return }
        let isReplacingActivity = activity != nil
        activity = newActivity
        pendingNextItem = nil
        activityChangeID = UUID()

        // Publish the new coordinated item as soon as the GroupActivity changes. Waiting for the
        // replacement media to finish loading leaves each participant coordinated against the old
        // item, so a seek can be applied locally while peers reject it for an identifier mismatch.
        // AetherEngine retains commands for this item until the replacement transport is ready.
        if isReplacingActivity,
           participantCount > 1,
           let playerController,
           playerController.isCoordinatedPlayback
        {
            playerController.beginCoordinatedPlayback(
                identifier: playbackIdentifier(for: newActivity),
                initialTime: newActivity.initialPosition,
            )
            lastCoordinatedActivityID = newActivity.activityID
        }
    }

    private func playbackIdentifier(for activity: StrimrWatchActivity) -> String {
        activity.activityID.uuidString
    }

    private func handleParticipantCountChange(previousCount: Int) {
        guard let playerController else { return }

        if participantCount <= 1 {
            if playerController.isCoordinatedPlayback {
                playerController.endCoordinatedPlayback(continueLocally: true)
            }
            return
        }

        guard previousCount <= 1,
              let session,
              let activity
        else { return }
        if playerController.isCoordinatedPlayback {
            playerController.endCoordinatedPlayback(continueLocally: true)
        }
        let shouldResumeInitialPlayback = pendingInitialResumeActivityID == activity.activityID
        // A first-time participant can reach this point while its media is still loading and its
        // local clock is zero. Use the activity's advertised progress for that first binding; only
        // preserve the local clock when reconnecting to an activity that was already coordinated.
        let isRejoiningCoordinatedActivity = lastCoordinatedActivityID == activity.activityID
        playerController.playbackCoordinator.coordinateWithSession(session)
        if shouldResumeInitialPlayback || isRejoiningCoordinatedActivity {
            pendingInitialResumeActivityID = nil
            playerController.beginCoordinatedPlaybackResumingFromCurrentState(
                identifier: playbackIdentifier(for: activity),
            )
        } else {
            playerController.beginCoordinatedPlayback(
                identifier: playbackIdentifier(for: activity),
                initialTime: activity.initialPosition,
            )
        }
        lastCoordinatedActivityID = activity.activityID
    }

    private func detach(continueLocally: Bool) {
        let continuingPlayer = continueLocally ? playerController : nil
        if playerController?.isCoordinatedPlayback == true {
            playerController?.endCoordinatedPlayback(continueLocally: continueLocally)
        }
        playerController = continuingPlayer
        pendingNextItem = nil
        pendingInitialResumeActivityID = nil
        session = nil
        activity = nil
        isInSession = false
        participantCount = 0
        sessionSubscriptions.removeAll()
    }
}

private enum SharePlayError: Error {
    case serverUnavailable
    case mediaUnavailable
}
