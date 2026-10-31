import AetherEngine
import Foundation
import Network
import Observation

@MainActor
@Observable
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let backgroundSessionIdentifier = "strimr.downloads.background"
    private struct EnqueueKey: Hashable {
        let ownerID: String
        let identity: MediaIdentity
    }

    private static let errorDomain = "Strimr.DownloadManager"
    private static let retryDelays: [TimeInterval] = [5, 30, 120]
    private static let transientURLErrors: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
    ]
    weak static var shared: DownloadManager?

    private(set) var items: [DownloadItem] = []
    private(set) var isOnWiFi: Bool?
    private(set) var storageSummary: DownloadStorageSummary = .empty
    private(set) var lastErrorMessage: String?
    private(set) var activeOwnerIDs: Set<String> = []

    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "strimr.downloads.network-monitor")
    @ObservationIgnored private var backgroundEventsCompletionHandler: (() -> Void)?
    @ObservationIgnored private var progressByTaskIdentifier: [Int: Double] = [:]
    @ObservationIgnored private var isLoadingPersistedState = false
    @ObservationIgnored private var ignoredCompletionIDs: Set<String> = []
    @ObservationIgnored private var servicesByServer: [ServerIdentity: MediaServices] = [:]
    @ObservationIgnored private var preparationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingRequestsByItemID: [String: URLRequest] = [:]
    @ObservationIgnored private var sidecarsByItemID: [String: [MediaDownloadSidecar]] = [:]
    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private let indexFileURL: URL
    @ObservationIgnored private var backgroundSession: URLSession!
    @ObservationIgnored private let offlineStore: OfflineStore?
    @ObservationIgnored private var enrichmentTasks: [ServerIdentity: Task<Void, Never>] = [:]
    @ObservationIgnored private var enqueuesInFlight: Set<EnqueueKey> = []
    @ObservationIgnored private var deletingIDs: Set<String> = []
    @ObservationIgnored private var activeFinalizations = 0
    @ObservationIgnored private var backgroundEventsFinished = false
    @ObservationIgnored private var retryAttempts: [String: Int] = [:]
    @ObservationIgnored private var retryTasks: [String: Task<Void, Never>] = [:]

    private static func buildBackgroundSession(delegate: URLSessionDownloadDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier,
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private static func buildDownloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    static func posterFileURL(downloadID: String) -> URL {
        buildDownloadsDirectory()
            .appendingPathComponent(downloadID, isDirectory: true)
            .appendingPathComponent("poster.jpg", isDirectory: false)
    }

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        downloadsDirectory = Self.buildDownloadsDirectory()
        indexFileURL = downloadsDirectory.appendingPathComponent("index.json")
        offlineStore = OfflineCoordinator.shared.store
        super.init()
        backgroundSession = Self.buildBackgroundSession(delegate: self)
        Self.shared = self
        configureStorage()
        loadPersistedState()
        startNetworkMonitoring()
        Task {
            await restoreRunningTasks()
        }
        refreshStorageSummary()
        OfflineCoordinator.shared.observeReachability { [weak self] server in
            self?.enrichDownloads(on: server, refreshingEnriched: true)
        }
    }

    /// Downloads belonging to the signed-in user(s); the rich app only ever shows these.
    var ownedItems: [DownloadItem] {
        items.filter(isOwnedByActiveUser)
    }

    /// Downloads of other profiles, accounts or signed-out users.
    var otherItems: [DownloadItem] {
        items.filter { !isOwnedByActiveUser($0) }
    }

    func isOwnedByActiveUser(_ item: DownloadItem) -> Bool {
        guard let ownerID = item.ownerID else { return false }
        return activeOwnerIDs.contains(ownerID)
    }

    var sortedItems: [DownloadItem] {
        sorted(items)
    }

    var sortedOwnedItems: [DownloadItem] {
        sorted(ownedItems)
    }

    var sortedOtherItems: [DownloadItem] {
        sorted(otherItems)
    }

    private func sorted(_ items: [DownloadItem]) -> [DownloadItem] {
        items.sorted { lhs, rhs in
            if lhs.status.isActive != rhs.status.isActive {
                return lhs.status.isActive
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var completedItems: [DownloadItem] {
        items.filter { $0.status == .completed }
    }

    var playableItems: [DownloadItem] {
        completedItems.filter { localVideoURL(for: $0) != nil }
    }

    var playableCount: Int {
        playableItems.count
    }

    func status(for identity: MediaIdentity) -> DownloadStatus? {
        latestItem(for: identity)?.status
    }

    func progress(for identity: MediaIdentity) -> Double? {
        latestItem(for: identity)?.progress
    }

    func useCellularData(for item: DownloadItem) async {
        guard let initialIndex = items.firstIndex(where: { $0.id == item.id }),
              items[initialIndex].status == .downloading,
              let currentTaskIdentifier = items[initialIndex].taskIdentifier
        else { return }

        let tasks = await allTasks()
        guard let currentTask = tasks.first(where: { $0.taskIdentifier == currentTaskIdentifier }),
              var request = currentTask.originalRequest ?? currentTask.currentRequest,
              let index = items.firstIndex(where: { $0.id == item.id }),
              items[index].taskIdentifier == currentTaskIdentifier
        else {
            let error = NSError(
                domain: Self.errorDomain,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to allow cellular access for this download."],
            )
            handleDownloadError(error)
            return
        }

        request.allowsCellularAccess = true
        request.allowsConstrainedNetworkAccess = true
        request.allowsExpensiveNetworkAccess = true

        let replacementTask = backgroundSession.downloadTask(with: request)
        replacementTask.taskDescription = item.id
        items[index].allowsCellularAccess = true
        items[index].progress = 0
        items[index].bytesWritten = 0
        items[index].totalBytes = 0
        items[index].taskIdentifier = replacementTask.taskIdentifier
        items[index].errorMessage = nil
        progressByTaskIdentifier.removeValue(forKey: currentTaskIdentifier)
        persistState()

        currentTask.cancel()
        replacementTask.resume()
    }

    func localVideoURL(for item: DownloadItem) -> URL? {
        guard item.status == .completed else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(item.metadata.videoFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func localPosterURL(for item: DownloadItem) -> URL? {
        guard let posterFileName = item.metadata.posterFileName else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(posterFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func localExternalSubtitles(for item: DownloadItem) -> [ExternalSubtitleTrack] {
        guard let fileName = item.metadata.subtitleFileName else { return [] }
        let url = downloadsDirectory
            .appendingPathComponent(item.id, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return [ExternalSubtitleTrack(
            url: url,
            name: item.metadata.subtitleTitle,
            language: item.metadata.subtitleLanguage,
            isForced: item.metadata.subtitleIsForced,
            formatHint: item.metadata.subtitleCodec,
        )]
    }

    func localMediaItem(for item: DownloadItem) -> MediaItem {
        let identity = item.identity ?? MediaIdentity(
            server: ServerIdentity(provider: .plex, id: "legacy-download:\(item.id)"),
            itemID: item.itemID,
        )
        return MediaItem(
            id: item.itemID,
            identity: identity,
            guid: item.metadata.guid,
            summary: item.metadata.summary,
            title: item.metadata.title,
            type: item.metadata.type,
            parentRatingKey: item.metadata.parentRatingKey,
            grandparentRatingKey: item.metadata.grandparentRatingKey,
            genres: item.metadata.genres,
            year: item.metadata.year,
            duration: item.metadata.duration,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: item.metadata.contentRating,
            studio: item.metadata.studio,
            tagline: item.metadata.tagline,
            thumbPath: localPosterURL(for: item) == nil ? nil : OfflineArtworkPath.downloadPoster(item.id),
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: item.metadata.viewCount,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: item.metadata.grandparentTitle,
            parentTitle: item.metadata.parentTitle,
            parentIndex: item.metadata.parentIndex,
            index: item.metadata.index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
    }

    /// Called whenever the session's services change: legacy downloads without owner on this server are attributed
    /// to the active user, and only this user's downloads are shown in the rich app.
    func activateSession(services: [MediaServices]) {
        activeOwnerIDs = Set(services.map(\.owner.id))
        for services in services {
            let owner = services.owner
            offlineStore?.register(owner: owner)
            adoptUnownedDownloads(for: owner)
            register(services: services)
            enrichDownloads(on: services.identity, refreshingEnriched: false)
        }
    }

    /// Enriches pending downloads of the active owner on `server` (legacy downloads, or ones queued offline) and,
    /// when coming back online, refreshes the pinned metadata of already enriched ones.
    private func enrichDownloads(on server: ServerIdentity, refreshingEnriched: Bool) {
        guard enrichmentTasks[server] == nil,
              let enrichment = OfflineCoordinator.shared.enrichment
        else { return }
        let candidates = ownedItems.filter { item in
            guard item.identity?.server == server else { return false }
            switch item.enrichmentState ?? .pending {
            case .pending:
                return true
            case .done:
                return refreshingEnriched
            case .orphaned:
                return false
            }
        }
        guard !candidates.isEmpty else { return }
        enrichmentTasks[server] = Task { [weak self] in
            defer { self?.enrichmentTasks[server] = nil }
            for candidate in candidates {
                guard !Task.isCancelled, let self,
                      let owner = owner(of: candidate),
                      let services = OfflineCoordinator.shared.reachableServices(for: owner)
                else { return }
                if candidate.enrichmentState == .done {
                    await enrichment.refresh(download: candidate, owner: owner, services: services)
                    continue
                }
                let state = await enrichment.enrich(download: candidate, owner: owner, services: services)
                guard let index = items.firstIndex(where: { $0.id == candidate.id }) else { continue }
                items[index].enrichmentState = state
                persistState()
            }
        }
    }

    private func enrichNewDownload(id: String, services: MediaServices) {
        guard let enrichment = OfflineCoordinator.shared.enrichment,
              let item = items.first(where: { $0.id == id })
        else { return }
        let owner = services.owner
        Task { [weak self] in
            let state = await enrichment.enrich(download: item, owner: owner, services: services)
            guard let self, let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].enrichmentState = state
            persistState()
        }
    }

    private func adoptUnownedDownloads(for owner: MediaOwner) {
        guard let offlineStore else { return }
        let adopted = items.indices.filter { items[$0].ownerID == nil && items[$0].identity?.server == owner.server }
        guard !adopted.isEmpty else { return }
        _ = offlineStore.assignOwner(owner, toUnownedDownloadsOn: owner.server)
        for index in adopted {
            items[index].ownerID = owner.id
            // A minimal pinned media row lets the rich app show the download before it is enriched.
            let media = localMediaItem(for: items[index])
            offlineStore.store(media: [media], owner: owner)
            offlineStore.pin(itemIDs: [media.id], downloadID: items[index].id, owner: owner)
        }
        persistState()
    }

    func owner(of item: DownloadItem) -> MediaOwner? {
        item.ownerID.flatMap { offlineStore?.owner(id: $0) }
    }

    /// Media used to play a download: the enriched pinned item when available, else the minimal local metadata.
    func playbackMedia(for item: DownloadItem) -> MediaItem {
        if let owner = owner(of: item), let media = offlineStore?.media(id: item.itemID, owner: owner) {
            return media
        }
        return localMediaItem(for: item)
    }

    /// The item vanished from the server: its downloads stay playable with the metadata they already have.
    func markOrphaned(itemID: String, owner: MediaOwner) {
        var changed = false
        for index in items.indices where items[index].itemID == itemID && items[index].ownerID == owner.id {
            items[index].enrichmentState = .orphaned
            changed = true
        }
        if changed {
            persistState()
        }
    }

    func register(services: MediaServices) {
        servicesByServer[services.identity] = services
        for item in items where item.identity?.server == services.identity && item.status == .preparing {
            startPreparationPolling(for: item.id, services: services)
        }
        startNextQueuedTransfer(on: services.identity)
    }

    func enqueueItem(
        itemID: String,
        quality: TranscodeQualityPreset? = nil,
        tracks: MediaTrackPreference = .serverDefault,
        version: MediaVersionRequest = .automatic,
        services: MediaServices,
    ) async {
        register(services: services)
        // Claim the media before asking the server to prepare it, so a double tap cannot queue it twice.
        let identity = MediaIdentity(server: services.identity, itemID: itemID)
        let key = EnqueueKey(ownerID: services.owner.id, identity: identity)
        guard !isAlreadyScheduled(for: identity, ownerID: services.owner.id),
              enqueuesInFlight.insert(key).inserted
        else { return }
        defer { enqueuesInFlight.remove(key) }
        do {
            let effectiveQuality = quality ?? settingsManager.downloads.qualityPreset
            let preparation = try await services.downloads.prepareDownload(
                itemID: itemID,
                quality: effectiveQuality,
                tracks: tracks,
                version: version,
            )
            try await enqueue(preparation, tracks: tracks, services: services)
        } catch {
            handleDownloadError(error)
        }
    }

    func enqueueItems(
        itemID: String,
        kind: MediaKind,
        quality: TranscodeQualityPreset? = nil,
        tracks: MediaTrackPreference = .serverDefault,
        version: MediaVersionRequest = .automatic,
        services: MediaServices,
    ) async {
        do {
            let media = try await services.downloads.downloadableItems(itemID: itemID, kind: kind)
            for item in media {
                guard !Task.isCancelled else { return }
                await enqueueItem(
                    itemID: item.id,
                    quality: quality,
                    tracks: tracks,
                    version: version,
                    services: services,
                )
            }
        } catch {
            handleDownloadError(error)
        }
    }

    private func enqueue(
        _ preparation: MediaDownloadPreparation,
        tracks: MediaTrackPreference,
        services: MediaServices,
    ) async throws {
        let mediaItem = preparation.media
        let owner = services.owner
        guard !isAlreadyScheduled(for: mediaItem.identity, ownerID: owner.id),
              mediaItem.kind == .movie || mediaItem.kind == .episode else { return }

        let id = UUID().uuidString
        let folderURL = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
        try createDirectoryIfNeeded(at: folderURL)
        try setExcludedFromBackup(at: folderURL)

        let posterFileName = await downloadPosterIfAvailable(
            for: mediaItem,
            services: services,
            destinationFolder: folderURL,
        )
        let metadata = DownloadedMediaMetadata(
            identity: mediaItem.identity,
            guid: mediaItem.guid,
            type: mediaItem.type,
            title: mediaItem.title,
            summary: mediaItem.summary,
            genres: mediaItem.genres,
            year: mediaItem.year,
            duration: mediaItem.duration,
            viewCount: mediaItem.viewCount,
            contentRating: mediaItem.contentRating,
            studio: mediaItem.studio,
            tagline: mediaItem.tagline,
            parentRatingKey: mediaItem.parentRatingKey,
            grandparentRatingKey: mediaItem.grandparentRatingKey,
            grandparentTitle: mediaItem.grandparentTitle,
            parentTitle: mediaItem.parentTitle,
            parentIndex: mediaItem.parentIndex,
            index: mediaItem.index,
            posterFileName: posterFileName,
            videoFileName: "video",
            fileSize: nil,
            requestedQuality: preparation.requestedQuality,
            effectiveQuality: preparation.effectiveQuality,
            audioTitle: preparation.audioTitle,
            subtitleTitle: preparation.subtitleTitle,
            versionID: preparation.versionID,
            versionLabel: preparation.versionLabel,
            createdAt: Date(),
        )
        let shouldQueue = preparation.remoteReference != nil && hasActiveTranscode(on: mediaItem.identity.server)
        let initialStatus: DownloadStatus = if shouldQueue {
            .queued
        } else if preparation.request == nil {
            .preparing
        } else {
            .downloading
        }
        items.append(DownloadItem(
            id: id,
            status: initialStatus,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            taskIdentifier: nil,
            remoteReference: preparation.remoteReference,
            trackPreference: tracks,
            errorMessage: nil,
            metadata: metadata,
            ownerID: owner.id,
            enrichmentState: .pending,
        ))
        offlineStore?.register(owner: owner)
        sidecarsByItemID[id] = preparation.sidecars
        if shouldQueue, let request = preparation.request {
            pendingRequestsByItemID[id] = request
        }
        persistState()
        enrichNewDownload(id: id, services: services)
        if shouldQueue {
            return
        } else if let request = preparation.request {
            startTransfer(itemID: id, request: request)
        } else {
            startPreparationPolling(for: id, services: services)
        }
    }

    func delete(_ item: DownloadItem) async {
        guard deletingIDs.insert(item.id).inserted else { return }
        defer { deletingIDs.remove(item.id) }
        let item = items.first(where: { $0.id == item.id }) ?? item
        let server = item.identity?.server
        preparationTasks.removeValue(forKey: item.id)?.cancel()
        retryTasks.removeValue(forKey: item.id)?.cancel()
        retryAttempts[item.id] = nil
        if let taskIdentifier = item.taskIdentifier, item.status.isActive {
            ignoredCompletionIDs.insert(item.id)
            await cancelTask(with: taskIdentifier)
        }
        if let reference = item.remoteReference,
           let server = item.identity?.server,
           let services = servicesByServer[server]
        {
            await services.downloads.cancelDownloadPreparation(reference)
        }

        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.removeItem(at: folderURL)
        }

        items.removeAll { $0.id == item.id }
        offlineStore?.deleteDownload(id: item.id)
        progressByTaskIdentifier.removeValue(forKey: item.taskIdentifier ?? -1)
        sidecarsByItemID[item.id] = nil
        pendingRequestsByItemID[item.id] = nil
        persistState()
        refreshStorageSummary()
        if let server {
            startNextQueuedTransfer(on: server)
        }
    }

    func deleteDownloads(ownerID: String) async {
        for item in items where item.ownerID == ownerID {
            await delete(item)
        }
    }

    func deleteOtherDownloads() async {
        for item in otherItems {
            await delete(item)
        }
    }

    func setBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundEventsCompletionHandler = handler
    }

    /// Tells iOS the background events are handled, but only once every finished transfer has been committed.
    private func finishBackgroundEventsIfIdle() {
        guard backgroundEventsFinished,
              activeFinalizations == 0,
              let handler = backgroundEventsCompletionHandler
        else { return }
        backgroundEventsFinished = false
        backgroundEventsCompletionHandler = nil
        handler()
    }

    func canRetry(_ item: DownloadItem) -> Bool {
        guard let current = items.first(where: { $0.id == item.id }),
              current.status == .failed,
              !deletingIDs.contains(current.id),
              isOwnedByActiveUser(current),
              !isEnqueueInFlight(current)
        else { return false }
        return !items.contains { other in
            other.id != current.id
                && other.identity == current.identity
                && other.ownerID == current.ownerID
                && other.status != .failed
        }
    }

    /// Restarts a failed download: resumes from saved partial data when iOS provided it, else starts over.
    func retry(_ item: DownloadItem) {
        guard canRetry(item) else { return }
        retryAttempts[item.id] = nil
        restart(item)
    }

    @discardableResult
    private func restart(_ item: DownloadItem) -> Bool {
        guard canRetry(item), let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        retryTasks.removeValue(forKey: item.id)?.cancel()

        items[index].errorMessage = nil
        let resumeURL = resumeDataURL(for: item.id)
        if items[index].remoteReference == nil, let data = try? Data(contentsOf: resumeURL), !data.isEmpty {
            let task = backgroundSession.downloadTask(withResumeData: data)
            task.taskDescription = item.id
            items[index].status = .downloading
            items[index].taskIdentifier = task.taskIdentifier
            persistState()
            task.resume()
            return true
        }

        if let reference = items[index].remoteReference,
           let server = items[index].identity?.server,
           let services = servicesByServer[server]
        {
            Task { await services.downloads.cancelDownloadPreparation(reference) }
        }
        items[index].status = .queued
        items[index].progress = 0
        items[index].bytesWritten = 0
        items[index].totalBytes = 0
        items[index].taskIdentifier = nil
        items[index].remoteReference = nil
        persistState()
        if let server = items[index].identity?.server {
            startNextQueuedTransfer(on: server)
        }
        return true
    }

    private func resumeDataURL(for itemID: String) -> URL {
        downloadsDirectory
            .appendingPathComponent(itemID, isDirectory: true)
            .appendingPathComponent("resume.data", isDirectory: false)
    }

    private func saveResumeData(from error: Error, itemID: String) {
        guard let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
              !data.isEmpty
        else {
            if !Self.isTransient(error) {
                try? FileManager.default.removeItem(at: resumeDataURL(for: itemID))
            }
            return
        }
        let url = resumeDataURL(for: itemID)
        do {
            try data.write(to: url, options: .atomic)
            try setExcludedFromBackup(at: url)
        } catch {
            ErrorReporter.capture(error)
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return transientURLErrors.contains(URLError.Code(rawValue: nsError.code))
        case errorDomain:
            return nsError.code == 408 || nsError.code == 429 || (500 ..< 600).contains(nsError.code)
        default:
            return false
        }
    }

    /// Retries transient failures a few times with growing delays; only runs while the app is alive.
    private func scheduleAutomaticRetry(for itemID: String, after error: Error) {
        guard Self.isTransient(error) else { return }
        let attempt = retryAttempts[itemID, default: 0]
        guard attempt < Self.retryDelays.count else { return }
        let delay = Self.retryDelays[attempt]
        retryTasks[itemID]?.cancel()
        retryTasks[itemID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            retryTasks[itemID] = nil
            guard let item = items.first(where: { $0.id == itemID }), item.status == .failed else { return }
            if restart(item) {
                retryAttempts[itemID] = attempt + 1
            }
        }
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.isOnWiFi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func configureStorage() {
        do {
            try createDirectoryIfNeeded(at: downloadsDirectory)
            try setExcludedFromBackup(at: downloadsDirectory)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
        )
    }

    private func setExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func downloadPosterIfAvailable(
        for mediaItem: MediaItem,
        services: MediaServices,
        destinationFolder: URL,
    ) async -> String? {
        do {
            guard let artwork = try await services.artwork.artwork(
                for: .playable(mediaItem),
                kind: .thumb,
                width: 480,
                height: 720,
            ) else { return nil }
            let data: Data = switch artwork {
            case let .data(value):
                value
            case let .url(url):
                try await URLSession.shared.data(from: url).0
            }
            guard !data.isEmpty else { return nil }
            let fileName = "poster.jpg"
            let destination = destinationFolder.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: destination, options: .atomic)
            try setExcludedFromBackup(at: destination)
            return fileName
        } catch {
            return nil
        }
    }

    private func isAlreadyScheduled(for identity: MediaIdentity, ownerID: String) -> Bool {
        items.contains { item in
            item.identity == identity && item.ownerID == ownerID && item.status != .failed
        }
    }

    private func isEnqueueInFlight(_ item: DownloadItem) -> Bool {
        guard let ownerID = item.ownerID, let identity = item.identity else { return false }
        return enqueuesInFlight.contains(EnqueueKey(ownerID: ownerID, identity: identity))
    }

    private func isJellyfinReference(_ reference: MediaDownloadRemoteReference?) -> Bool {
        if case .jellyfin? = reference {
            return true
        }
        return false
    }

    private func hasActiveTranscode(on server: ServerIdentity) -> Bool {
        items.contains {
            $0.identity?.server == server
                && $0.remoteReference != nil
                && ($0.status == .preparing || $0.status == .downloading)
        }
    }

    func latestItem(for identity: MediaIdentity) -> DownloadItem? {
        items
            .filter { $0.identity == identity && isOwnedByActiveUser($0) }
            .max { $0.createdAt < $1.createdAt }
    }

    private func handleDownloadError(_ error: Error) {
        guard !Task.isCancelled, !error.isCancellation else { return }
        lastErrorMessage = error.localizedDescription
        ErrorReporter.capture(error)
    }

    private func persistState() {
        guard !isLoadingPersistedState else { return }
        do {
            if let offlineStore {
                try offlineStore.save(downloads: items)
            } else {
                // The offline database could not be opened: keep the legacy index so downloads are not lost.
                try JSONEncoder().encode(items).write(to: indexFileURL, options: .atomic)
            }
        } catch {
            ErrorReporter.capture(error)
        }
    }

    private func loadPersistedState() {
        isLoadingPersistedState = true
        defer { isLoadingPersistedState = false }
        guard let offlineStore else {
            if let data = try? Data(contentsOf: indexFileURL) {
                items = (try? JSONDecoder().decode([DownloadItem].self, from: data)) ?? []
            }
            return
        }

        migrateLegacyIndexIfNeeded(into: offlineStore)
        do {
            items = try offlineStore.allDownloads()
        } catch {
            ErrorReporter.capture(error)
            items = []
        }
    }

    /// One-time structural migration of `index.json` into the offline database. The transfer state is kept as is so
    /// `restoreRunningTasks` can resume running transfers; enrichment happens later once the server is reachable.
    private func migrateLegacyIndexIfNeeded(into store: OfflineStore) {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            var legacyItems = try JSONDecoder().decode([DownloadItem].self, from: data)
            for index in legacyItems.indices {
                legacyItems[index].ownerID = nil
                legacyItems[index].enrichmentState = .pending
            }
            try store.save(downloads: legacyItems)
            let migratedURL = indexFileURL.appendingPathExtension("migrated")
            try? FileManager.default.removeItem(at: migratedURL)
            try FileManager.default.moveItem(at: indexFileURL, to: migratedURL)
        } catch {
            ErrorReporter.capture(error)
        }
    }

    private func refreshStorageSummary() {
        let downloadsBytes = items.reduce(into: Int64(0)) { partialResult, item in
            if item.status == .completed {
                partialResult += item.metadata.fileSize ?? 0
            }
        }

        let fileSystemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let totalBytes = (fileSystemAttributes?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let freeBytes = (fileSystemAttributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let usedBytes = max(0, totalBytes - freeBytes)

        storageSummary = DownloadStorageSummary(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            availableBytes: freeBytes,
            downloadsBytes: downloadsBytes,
        )
    }

    private func persistMetadataFile(for item: DownloadItem) {
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let metadataURL = folderURL.appendingPathComponent("metadata.json", isDirectory: false)

        do {
            let data = try JSONEncoder().encode(item.metadata)
            try data.write(to: metadataURL, options: .atomic)
            try setExcludedFromBackup(at: metadataURL)
        } catch {}
    }

    private func updateItem(_ transform: (inout DownloadItem) -> Void, matchingTask task: URLSessionTask) {
        guard let index = itemIndex(for: task) else { return }
        transform(&items[index])
    }

    private func itemIndex(for task: URLSessionTask) -> Int? {
        if let description = task.taskDescription {
            guard let index = items.firstIndex(where: { $0.id == description }),
                  items[index].taskIdentifier == task.taskIdentifier
            else { return nil }
            return index
        }

        return items.firstIndex(where: { $0.taskIdentifier == task.taskIdentifier })
    }

    private func restoreRunningTasks() async {
        let tasks = await allTasks()
        let runningTaskIDs = Set(tasks.map(\.taskIdentifier))

        for index in items.indices {
            if let taskIdentifier = items[index].taskIdentifier, runningTaskIDs.contains(taskIdentifier) {
                items[index].status = .downloading
                items[index].errorMessage = nil
            } else if items[index].status == .preparing || items[index].status == .queued {
                continue
            } else if items[index].status.isActive {
                // The task identifier is kept so a completion that iOS delivers after this restore still matches.
                items[index].status = .failed
                items[index].errorMessage = String(localized: "downloads.status.interrupted")
            }
        }

        persistState()
    }

    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            backgroundSession.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private func cancelTask(with identifier: Int) async {
        let tasks = await allTasks()
        tasks.first { $0.taskIdentifier == identifier }?.cancel()
    }

    private func startTransfer(itemID: String, request sourceRequest: URLRequest) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var request = sourceRequest
        let allowsCellularAccess = items[index].allowsCellularAccess
            ?? !settingsManager.downloads.wifiOnly
        request.allowsCellularAccess = allowsCellularAccess
        request.allowsConstrainedNetworkAccess = allowsCellularAccess
        request.allowsExpensiveNetworkAccess = allowsCellularAccess
        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = itemID
        items[index].allowsCellularAccess = allowsCellularAccess
        items[index].status = .downloading
        items[index].progress = 0
        items[index].taskIdentifier = task.taskIdentifier
        items[index].errorMessage = nil
        persistState()
        task.resume()
    }

    private func startPreparationPolling(for itemID: String, services: MediaServices) {
        guard preparationTasks[itemID] == nil else { return }
        preparationTasks[itemID] = Task { [weak self] in
            guard let self else { return }
            defer { preparationTasks[itemID] = nil }
            while !Task.isCancelled {
                guard let current = items.first(where: { $0.id == itemID }),
                      current.status == .preparing,
                      let reference = current.remoteReference
                else { return }
                do {
                    let update = try await services.downloads.refreshDownloadPreparation(reference)
                    guard let index = items.firstIndex(where: { $0.id == itemID }),
                          items[index].status == .preparing
                    else { return }
                    switch update {
                    case let .preparing(progress):
                        if let progress {
                            items[index].progress = progress
                        }
                        persistState()
                    case let .ready(request, sidecars):
                        sidecarsByItemID[itemID] = sidecars
                        startTransfer(itemID: itemID, request: request)
                        return
                    case let .failed(message):
                        items[index].status = .failed
                        items[index].errorMessage = message
                        let server = items[index].identity?.server
                        persistState()
                        await services.downloads.cancelDownloadPreparation(reference)
                        if let server {
                            startNextQueuedTransfer(on: server)
                        }
                        return
                    }
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    ErrorReporter.capture(error)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startNextQueuedTransfer(on server: ServerIdentity) {
        guard !hasActiveTranscode(on: server),
              let services = servicesByServer[server],
              let item = items
                  .filter({ $0.identity?.server == server && $0.status == .queued && !deletingIDs.contains($0.id) })
                  .min(by: { $0.createdAt < $1.createdAt }),
              preparationTasks[item.id] == nil
        else { return }

        let cachedRequest = pendingRequestsByItemID.removeValue(forKey: item.id)
        // A Jellyfin request waiting in the queue may carry a stale token or server address: prepare it again.
        if let cachedRequest, !isJellyfinReference(item.remoteReference) {
            startTransfer(itemID: item.id, request: cachedRequest)
            startNextQueuedTransfer(on: server)
            return
        }
        if case .plex? = item.remoteReference {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].status = .preparing
            persistState()
            startPreparationPolling(for: item.id, services: services)
            return
        }

        preparationTasks[item.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                // While the item is preparing, the polling task owns this slot and clears it itself.
                if items.first(where: { $0.id == item.id })?.status != .preparing {
                    preparationTasks[item.id] = nil
                }
            }
            do {
                let preparation = try await services.downloads.prepareDownload(
                    itemID: item.itemID,
                    quality: item.metadata.requestedQuality,
                    tracks: item.trackPreference ?? .serverDefault,
                    version: item.metadata.versionID.map { .explicit(versionID: $0) } ?? .automatic,
                )
                guard let index = items.firstIndex(where: { $0.id == item.id }),
                      items[index].status == .queued,
                      !deletingIDs.contains(item.id)
                else { return }
                items[index].remoteReference = preparation.remoteReference
                items[index].metadata.effectiveQuality = preparation.effectiveQuality
                items[index].metadata.audioTitle = preparation.audioTitle
                items[index].metadata.subtitleTitle = preparation.subtitleTitle
                items[index].metadata.versionID = preparation.versionID
                items[index].metadata.versionLabel = preparation.versionLabel
                sidecarsByItemID[item.id] = preparation.sidecars
                persistState()
                if let request = preparation.request {
                    startTransfer(itemID: item.id, request: request)
                    startNextQueuedTransfer(on: server)
                } else {
                    items[index].status = .preparing
                    persistState()
                    preparationTasks[item.id] = nil
                    startPreparationPolling(for: item.id, services: services)
                }
            } catch {
                guard !Task.isCancelled, !error.isCancellation,
                      let index = items.firstIndex(where: { $0.id == item.id })
                else { return }
                items[index].status = .failed
                items[index].errorMessage = error.localizedDescription
                persistState()
                ErrorReporter.capture(error)
                startNextQueuedTransfer(on: server)
            }
        }
    }

    private func sanitizeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "_",
            options: .regularExpression,
        )
    }

    private func resolveDownloadDestination(
        for item: DownloadItem,
        response: URLResponse?,
    ) -> URL {
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let suggestedName = (response?.suggestedFilename).flatMap { sanitizeFileName($0) }
        let fallback = sanitizeFileName(item.metadata.title) + ".mp4"
        let fileName = suggestedName?.isEmpty == false ? suggestedName! : fallback
        return folderURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func completeDownload(task: URLSessionDownloadTask, stagedLocation: URL) async {
        guard let index = itemIndex(for: task) else {
            try? FileManager.default.removeItem(at: stagedLocation)
            return
        }
        let itemID = items[index].id

        // A server error body (401, 404, 5xx) or an empty file must never be committed as a finished video.
        if let response = task.response as? HTTPURLResponse, !(200 ..< 300).contains(response.statusCode) {
            try? FileManager.default.removeItem(at: stagedLocation)
            failDownload(task: task, error: NSError(
                domain: Self.errorDomain,
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(
                    forStatusCode: response.statusCode,
                )],
            ))
            return
        }
        let stagedSize = (try? FileManager.default.attributesOfItem(atPath: stagedLocation.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        guard stagedSize > 0 else {
            try? FileManager.default.removeItem(at: stagedLocation)
            failDownload(task: task, error: NSError(
                domain: Self.errorDomain,
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "downloads.status.failed")],
            ))
            return
        }

        activeFinalizations += 1
        var finalizationPending = true
        defer {
            if finalizationPending {
                activeFinalizations -= 1
                finishBackgroundEventsIfIdle()
            }
        }

        let destination = resolveDownloadDestination(for: items[index], response: task.response)

        do {
            try createDirectoryIfNeeded(at: destination.deletingLastPathComponent())

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.moveItem(at: stagedLocation, to: destination)
            try setExcludedFromBackup(at: destination)

            let fileAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0

            items[index].status = .completed
            items[index].progress = 1
            items[index].bytesWritten = fileSize
            items[index].totalBytes = fileSize
            items[index].taskIdentifier = nil
            items[index].errorMessage = nil
            items[index].metadata.videoFileName = destination.lastPathComponent
            items[index].metadata.fileSize = fileSize
            let reference = items[index].remoteReference
            let server = items[index].identity?.server

            // The video is committed before any optional network work below.
            persistState()
            try? FileManager.default.removeItem(at: resumeDataURL(for: itemID))
            retryAttempts[itemID] = nil
            finalizationPending = false
            activeFinalizations -= 1
            finishBackgroundEventsIfIdle()

            await persistSidecars(forItemID: itemID, folderURL: destination.deletingLastPathComponent())

            if let reference, let server, let services = servicesByServer[server] {
                await services.downloads.cancelDownloadPreparation(reference)
            }

            if let currentIndex = items.firstIndex(where: { $0.id == itemID }) {
                items[currentIndex].remoteReference = nil
                persistMetadataFile(for: items[currentIndex])
                persistState()
            }
            refreshStorageSummary()
            if let server {
                startNextQueuedTransfer(on: server)
            }
        } catch {
            guard let currentIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
            items[currentIndex].status = .failed
            items[currentIndex].taskIdentifier = nil
            items[currentIndex].errorMessage = error.localizedDescription
            persistState()
            if let server = items[currentIndex].identity?.server {
                startNextQueuedTransfer(on: server)
            }
        }
    }

    private func persistSidecars(forItemID itemID: String, folderURL: URL) async {
        guard let startIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        if sidecarsByItemID[itemID] == nil,
           let server = items[startIndex].identity?.server,
           let services = servicesByServer[server]
        {
            let remoteItemID = items[startIndex].itemID
            let tracks = items[startIndex].trackPreference ?? .serverDefault
            let versionID = items[startIndex].metadata.versionID
            do {
                sidecarsByItemID[itemID] = try await services.downloads.downloadSidecars(
                    itemID: remoteItemID,
                    tracks: tracks,
                    versionID: versionID,
                )
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
        guard let sidecar = sidecarsByItemID[itemID]?.first,
              let requestIndex = items.firstIndex(where: { $0.id == itemID })
        else { return }
        do {
            var request = sidecar.request
            let allowsCellularAccess = items[requestIndex].allowsCellularAccess
                ?? !settingsManager.downloads.wifiOnly
            request.allowsCellularAccess = allowsCellularAccess
            request.allowsConstrainedNetworkAccess = allowsCellularAccess
            request.allowsExpensiveNetworkAccess = allowsCellularAccess
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode,
                  !data.isEmpty
            else { return }
            let fileName = "subtitle.\(sanitizeFileName(sidecar.fileExtension))"
            let url = folderURL.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: url, options: .atomic)
            try setExcludedFromBackup(at: url)
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            items[index].metadata.subtitleFileName = fileName
            items[index].metadata.subtitleTitle = sidecar.title
            items[index].metadata.subtitleLanguage = sidecar.language
            items[index].metadata.subtitleCodec = sidecar.codec
            items[index].metadata.subtitleIsForced = sidecar.isForced
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
                .int64Value ?? 0
            items[index].metadata.fileSize = (items[index].metadata.fileSize ?? 0) + size
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
        sidecarsByItemID[itemID] = nil
    }

    private nonisolated static func stageDownloadFile(at location: URL) throws -> URL {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("strimr-download-staging", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true,
        )

        let stagedURL = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            try FileManager.default.removeItem(at: stagedURL)
        }
        try FileManager.default.moveItem(at: location, to: stagedURL)
        return stagedURL
    }

    private func failDownload(task: URLSessionTask, error: Error) {
        guard let index = itemIndex(for: task) else { return }
        let itemID = items[index].id
        guard !ignoredCompletionIDs.contains(itemID) else {
            ignoredCompletionIDs.remove(itemID)
            return
        }

        // Transcodes are torn down on failure, so only direct downloads can be resumed.
        if items[index].remoteReference == nil {
            saveResumeData(from: error, itemID: itemID)
        }
        items[index].status = .failed
        items[index].taskIdentifier = nil
        items[index].errorMessage = error.localizedDescription
        let reference = items[index].remoteReference
        let server = items[index].identity?.server
        persistState()
        if let reference, let server, let services = servicesByServer[server] {
            Task { await services.downloads.cancelDownloadPreparation(reference) }
        }
        if let server {
            startNextQueuedTransfer(on: server)
        }
        scheduleAutomaticRetry(for: itemID, after: error)
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
    ) {
        Task { @MainActor in
            guard totalBytesExpectedToWrite > 0 else { return }
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let previousProgress = progressByTaskIdentifier[downloadTask.taskIdentifier] ?? -1
            guard progress - previousProgress >= 0.01 || progress == 1 else { return }
            progressByTaskIdentifier[downloadTask.taskIdentifier] = progress

            updateItem({ item in
                item.status = .downloading
                item.progress = progress
                item.bytesWritten = totalBytesWritten
                item.totalBytes = totalBytesExpectedToWrite
            }, matchingTask: downloadTask)
            persistState()
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL,
    ) {
        do {
            let stagedURL = try Self.stageDownloadFile(at: location)
            Task { @MainActor in
                await completeDownload(task: downloadTask, stagedLocation: stagedURL)
            }
        } catch {
            Task { @MainActor in
                failDownload(task: downloadTask, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?,
    ) {
        guard let error else { return }
        Task { @MainActor in
            failDownload(task: task, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        Task { @MainActor in
            guard backgroundEventsCompletionHandler != nil else { return }
            backgroundEventsFinished = true
            finishBackgroundEventsIfIdle()
        }
    }
}
