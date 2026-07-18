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
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let groupStateObserver = GroupStateObserver()
    @ObservationIgnored private var session: GroupSession<StrimrWatchActivity>?
    @ObservationIgnored private var playbackLauncher: PlaybackLauncher?
    @ObservationIgnored private weak var playerController: PlayerController?
    @ObservationIgnored private var sessionSubscriptions: Set<AnyCancellable> = []
    @ObservationIgnored private var sessionListener: Task<Void, Never>?
    @ObservationIgnored private var locallyPreparedActivityIDs: Set<UUID> = []
    @ObservationIgnored private var pendingNextItem: PlexItem?
    @ObservationIgnored private var lastLaunchedActivityID: UUID?
    @ObservationIgnored private var sharingPresentationActivityID: UUID?

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        self.context = context
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
        type: PlexItemType,
        title: String,
        initialPosition: Double,
    ) -> StrimrWatchActivity? {
        guard let serverIdentifier = sessionManager.plexServer?.clientIdentifier else {
            errorMessage = String(localized: "sharePlay.error.serverUnavailable")
            return nil
        }
        let activity = StrimrWatchActivity(
            activityID: UUID(),
            serverIdentifier: serverIdentifier,
            ratingKey: ratingKey,
            mediaType: type,
            title: title,
            initialPosition: max(0, initialPosition),
        )
        return activity
    }

    func activate(
        ratingKey: String,
        type: PlexItemType,
        title: String,
        initialPosition: Double,
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
        ) else { return }

        await activate(activity)
    }

    func activate(_ activity: StrimrWatchActivity) async {
        guard !isActivating else { return }

        isActivating = true
        locallyPreparedActivityIDs.insert(activity.activityID)
        defer { isActivating = false }

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
        guard let session, let activity, activity.ratingKey == ratingKey else { return }
        controller.playbackCoordinator.coordinateWithSession(session)
        controller.beginCoordinatedPlayback(
            identifier: activity.ratingKey,
            initialTime: activity.initialPosition,
        )
    }

    func playerDidLoad(ratingKey: String) {
        guard let activity, activity.ratingKey == ratingKey else { return }
        playerController?.beginCoordinatedPlayback(
            identifier: ratingKey,
            initialTime: activity.initialPosition,
        )
        if locallyPreparedActivityIDs.remove(activity.activityID) != nil {
            playerController?.resume()
        }
    }

    func updateToNextEpisode(_ item: PlexItem) {
        pendingNextItem = item
        publishPendingNextItemIfLeader()
    }

    private func publishPendingNextItemIfLeader() {
        guard let session, isLocalLeader, let item = pendingNextItem else { return }
        let next = StrimrWatchActivity(
            activityID: UUID(),
            serverIdentifier: session.activity.serverIdentifier,
            ratingKey: item.ratingKey,
            mediaType: item.type,
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
        do {
            try await ensureAccess(to: newSession.activity)
        } catch {
            locallyPreparedActivityIDs.remove(newSession.activity.activityID)
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = String(localized: "sharePlay.error.mediaUnavailable")
            newSession.leave()
            return
        }

        session?.leave()
        sessionSubscriptions.removeAll()
        session = newSession
        activity = newSession.activity
        isInSession = true
        participantCount = newSession.activeParticipants.count

        newSession.$activity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity in self?.handleActivityChange(activity) }
            .store(in: &sessionSubscriptions)

        newSession.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                self?.participantCount = participants.count
                self?.publishPendingNextItemIfLeader()
            }
            .store(in: &sessionSubscriptions)

        newSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard case .invalidated = state else { return }
                self?.detach(continueLocally: true)
            }
            .store(in: &sessionSubscriptions)

        newSession.join()
        if let playerController, let activity {
            playerController.playbackCoordinator.coordinateWithSession(newSession)
            playerController.beginCoordinatedPlayback(
                identifier: activity.ratingKey,
                initialTime: activity.initialPosition,
            )
        } else if sharingPresentationActivityID != newSession.activity.activityID {
            await launchPlaybackIfNeeded(for: newSession.activity)
        }
    }

    private func launchPlaybackIfNeeded(for activity: StrimrWatchActivity) async {
        guard lastLaunchedActivityID != activity.activityID,
              let playbackLauncher
        else { return }
        lastLaunchedActivityID = activity.activityID
        await playbackLauncher.play(
            ratingKey: activity.ratingKey,
            type: activity.mediaType,
            shouldResumeFromOffset: false,
        )
    }

    private func ensureAccess(to activity: StrimrWatchActivity) async throws {
        if sessionManager.plexServer?.clientIdentifier != activity.serverIdentifier {
            let resources = try await ResourceRepository(context: context).getAvailableResources()
            guard let server = resources.first(where: {
                $0.clientIdentifier == activity.serverIdentifier
            }) else {
                throw SharePlayError.serverUnavailable
            }
            try await sessionManager.selectServer(server)
        }
        let repository = try MetadataRepository(context: context)
        let response = try await repository.getMetadata(ratingKey: activity.ratingKey)
        guard response.mediaContainer.metadata?.isEmpty == false else {
            throw SharePlayError.mediaUnavailable
        }
    }

    private func handleActivityChange(_ newActivity: StrimrWatchActivity) {
        guard activity != newActivity else { return }
        activity = newActivity
        pendingNextItem = nil
        activityChangeID = UUID()
    }

    private func detach(continueLocally: Bool) {
        playerController?.endCoordinatedPlayback(continueLocally: continueLocally)
        playerController = nil
        pendingNextItem = nil
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
