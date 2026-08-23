import AetherEngine
import Foundation
import Network
import Observation

@MainActor
@Observable
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let backgroundSessionIdentifier = "strimr.downloads.background"
    weak static var shared: DownloadManager?

    private(set) var items: [DownloadItem] = []
    private(set) var isOffline = false
    private(set) var isOnWiFi = false
    private(set) var storageSummary: DownloadStorageSummary = .empty
    private(set) var lastErrorMessage: String?

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

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        downloadsDirectory = Self.buildDownloadsDirectory()
        indexFileURL = downloadsDirectory.appendingPathComponent("index.json")
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
    }

    var sortedItems: [DownloadItem] {
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

    var shouldForceOfflineDownloads: Bool {
        isOffline
    }

    func status(for identity: MediaIdentity) -> DownloadStatus? {
        latestItem(for: identity)?.status
    }

    func progress(for identity: MediaIdentity) -> Double? {
        latestItem(for: identity)?.progress
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
            thumbPath: nil,
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
        tracks: MediaDownloadTrackPreference = .serverDefault,
        services: MediaServices,
    ) async {
        register(services: services)
        do {
            let effectiveQuality = quality ?? settingsManager.downloads.qualityPreset
            let preparation = try await services.downloads.prepareDownload(
                itemID: itemID,
                quality: effectiveQuality,
                tracks: tracks,
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
        tracks: MediaDownloadTrackPreference = .serverDefault,
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
                    services: services,
                )
            }
        } catch {
            handleDownloadError(error)
        }
    }

    func enqueueItem(itemID: String, context: PlexAPIContext) async {
        guard let services = PlexMediaServicesFactory.make(context: context, sessionManager: nil) else { return }
        await enqueueItem(itemID: itemID, services: services)
    }

    func enqueueSeason(itemID: String, context: PlexAPIContext) async {
        guard let services = PlexMediaServicesFactory.make(context: context, sessionManager: nil) else { return }
        await enqueueItems(itemID: itemID, kind: .season, services: services)
    }

    func enqueueShow(itemID: String, context: PlexAPIContext) async {
        guard let services = PlexMediaServicesFactory.make(context: context, sessionManager: nil) else { return }
        await enqueueItems(itemID: itemID, kind: .series, services: services)
    }

    private func enqueue(
        _ preparation: MediaDownloadPreparation,
        tracks: MediaDownloadTrackPreference,
        services: MediaServices,
    ) async throws {
        let mediaItem = preparation.media
        guard !isAlreadyScheduled(for: mediaItem.identity) else { return }
        guard mediaItem.kind == .movie || mediaItem.kind == .episode else { return }

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
        ))
        sidecarsByItemID[id] = preparation.sidecars
        if shouldQueue, let request = preparation.request {
            pendingRequestsByItemID[id] = request
        }
        persistState()
        if shouldQueue {
            return
        } else if let request = preparation.request {
            startTransfer(itemID: id, request: request)
        } else {
            startPreparationPolling(for: id, services: services)
        }
    }

    func delete(_ item: DownloadItem) async {
        let server = item.identity?.server
        preparationTasks.removeValue(forKey: item.id)?.cancel()
        if let taskIdentifier = item.taskIdentifier {
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
        progressByTaskIdentifier.removeValue(forKey: item.taskIdentifier ?? -1)
        sidecarsByItemID[item.id] = nil
        pendingRequestsByItemID[item.id] = nil
        persistState()
        refreshStorageSummary()
        if let server {
            startNextQueuedTransfer(on: server)
        }
    }

    func setBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundEventsCompletionHandler = handler
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.isOffline = path.status != .satisfied
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

    private func isAlreadyScheduled(for identity: MediaIdentity) -> Bool {
        items.contains { item in
            item.identity == identity && item.status != .failed
        }
    }

    private func hasActiveTranscode(on server: ServerIdentity) -> Bool {
        items.contains {
            $0.identity?.server == server
                && $0.remoteReference != nil
                && ($0.status == .preparing || $0.status == .downloading)
        }
    }

    private func latestItem(for identity: MediaIdentity) -> DownloadItem? {
        items
            .filter { $0.identity == identity }
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
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {}
    }

    private func loadPersistedState() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        isLoadingPersistedState = true
        defer { isLoadingPersistedState = false }

        do {
            let data = try Data(contentsOf: indexFileURL)
            items = try JSONDecoder().decode([DownloadItem].self, from: data)
        } catch {
            items = []
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
        if let description = task.taskDescription,
           let descriptionIndex = items.firstIndex(where: { $0.id == description })
        {
            return descriptionIndex
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
            } else if items[index].status == .preparing {
                continue
            } else if items[index].status.isActive {
                items[index].status = .failed
                items[index].errorMessage = String(localized: "downloads.status.interrupted")
                items[index].taskIdentifier = nil
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
        if settingsManager.downloads.wifiOnly {
            request.allowsCellularAccess = false
            request.allowsConstrainedNetworkAccess = false
            request.allowsExpensiveNetworkAccess = false
        }
        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = itemID
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
                guard let index = items.firstIndex(where: { $0.id == itemID }),
                      items[index].status == .preparing,
                      let reference = items[index].remoteReference
                else { return }
                do {
                    switch try await services.downloads.refreshDownloadPreparation(reference) {
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
                        persistState()
                        await services.downloads.cancelDownloadPreparation(reference)
                        if let server = items[index].identity?.server {
                            startNextQueuedTransfer(on: server)
                        }
                        return
                    }
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    if !isOffline {
                        ErrorReporter.capture(error)
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startNextQueuedTransfer(on server: ServerIdentity) {
        guard !hasActiveTranscode(on: server),
              let services = servicesByServer[server],
              let item = items
              .filter({ $0.identity?.server == server && $0.status == .queued })
              .min(by: { $0.createdAt < $1.createdAt }),
              preparationTasks[item.id] == nil
        else { return }

        if let request = pendingRequestsByItemID.removeValue(forKey: item.id) {
            startTransfer(itemID: item.id, request: request)
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
            defer { preparationTasks[item.id] = nil }
            do {
                let preparation = try await services.downloads.prepareDownload(
                    itemID: item.itemID,
                    quality: item.metadata.requestedQuality,
                    tracks: item.trackPreference ?? .serverDefault,
                )
                guard let index = items.firstIndex(where: { $0.id == item.id }),
                      items[index].status == .queued
                else { return }
                items[index].remoteReference = preparation.remoteReference
                items[index].metadata.effectiveQuality = preparation.effectiveQuality
                items[index].metadata.audioTitle = preparation.audioTitle
                items[index].metadata.subtitleTitle = preparation.subtitleTitle
                sidecarsByItemID[item.id] = preparation.sidecars
                persistState()
                if let request = preparation.request {
                    startTransfer(itemID: item.id, request: request)
                } else {
                    items[index].status = .preparing
                    persistState()
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
        guard let index = itemIndex(for: task) else { return }
        let item = items[index]
        let destination = resolveDownloadDestination(for: item, response: task.response)

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

            await persistSidecars(forItemAt: index, folderURL: destination.deletingLastPathComponent())

            if let reference = items[index].remoteReference,
               let server = items[index].identity?.server,
               let services = servicesByServer[server]
            {
                await services.downloads.cancelDownloadPreparation(reference)
                items[index].remoteReference = nil
            }

            persistMetadataFile(for: items[index])
            persistState()
            refreshStorageSummary()
            if let server = items[index].identity?.server {
                startNextQueuedTransfer(on: server)
            }
        } catch {
            items[index].status = .failed
            items[index].taskIdentifier = nil
            items[index].errorMessage = error.localizedDescription
            persistState()
            if let server = items[index].identity?.server {
                startNextQueuedTransfer(on: server)
            }
        }
    }

    private func persistSidecars(forItemAt index: Int, folderURL: URL) async {
        let itemID = items[index].id
        if sidecarsByItemID[itemID] == nil,
           let server = items[index].identity?.server,
           let services = servicesByServer[server]
        {
            do {
                sidecarsByItemID[itemID] = try await services.downloads.downloadSidecars(
                    itemID: items[index].itemID,
                    tracks: items[index].trackPreference ?? .serverDefault,
                )
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
        guard let sidecar = sidecarsByItemID[itemID]?.first else { return }
        do {
            var request = sidecar.request
            if settingsManager.downloads.wifiOnly {
                request.allowsCellularAccess = false
                request.allowsConstrainedNetworkAccess = false
                request.allowsExpensiveNetworkAccess = false
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200 ..< 300 ~= httpResponse.statusCode,
                  !data.isEmpty
            else { return }
            let fileName = "subtitle.\(sanitizeFileName(sidecar.fileExtension))"
            let url = folderURL.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: url, options: .atomic)
            try setExcludedFromBackup(at: url)
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
            backgroundEventsCompletionHandler?()
            backgroundEventsCompletionHandler = nil
        }
    }
}
