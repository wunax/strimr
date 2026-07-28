import CoreGraphics
import Foundation

private nonisolated final class PlexBIFImageBox {
    let thumbnail: PlexBIFThumbnail

    init(_ thumbnail: PlexBIFThumbnail) {
        self.thumbnail = thumbnail
    }
}

private nonisolated final class PlexBIFMemoryCache: @unchecked Sendable {
    private static let sharedInstance = PlexBIFMemoryCache()
    nonisolated static var shared: PlexBIFMemoryCache { sharedInstance }

    private let cache: NSCache<NSString, PlexBIFImageBox> = {
        let cache = NSCache<NSString, PlexBIFImageBox>()
        cache.countLimit = 64
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    nonisolated func thumbnail(key: String, frameIndex: Int) -> PlexBIFThumbnail? {
        cache.object(forKey: "\(key):\(frameIndex)" as NSString)?.thumbnail
    }

    nonisolated func store(
        _ thumbnail: PlexBIFThumbnail,
        key: String,
        frameIndex: Int,
    ) {
        let cost = thumbnail.image.bytesPerRow * thumbnail.image.height
        cache.setObject(
            PlexBIFImageBox(thumbnail),
            forKey: "\(key):\(frameIndex)" as NSString,
            cost: cost,
        )
    }
}

actor PlexBIFThumbnailProvider {
    private struct PreparedArchive: Sendable {
        let archive: PlexBIFArchive
        let metadata: PlexBIFCacheMetadata
        let shouldRevalidate: Bool
    }

    private let source: PlexBIFSource
    private let intervalMilliseconds = 10_000
    private let diskCache: PlexBIFDiskCache
    private let memoryCache = PlexBIFMemoryCache.shared
    private let cacheKey: String

    private var archive: PlexBIFArchive?
    private var preparationTask: Task<PreparedArchive?, Never>?
    private var refreshTask: Task<Void, Never>?
    private var isUnavailable = false
    private var isCancelled = false

    init(
        source: PlexBIFSource,
        diskCache: PlexBIFDiskCache = .shared,
    ) {
        self.source = source
        self.diskCache = diskCache
        cacheKey = PlexBIFDiskCache.key(
            serverIdentity: source.serverIdentity,
            partID: source.partID,
            intervalMilliseconds: intervalMilliseconds,
        )
    }

    func prepare() async {
        _ = await preparedArchive()
    }

    func thumbnail(at seconds: Double) async -> PlexBIFThumbnail? {
        guard let archive = await preparedArchive(), !isCancelled else {
            return nil
        }
        let frameIndex = archive.frameIndex(at: seconds)
        if let hit = memoryCache.thumbnail(key: cacheKey, frameIndex: frameIndex) {
            return hit
        }

        let result = await Task.detached(priority: .userInitiated) {
            try? archive.thumbnail(frameIndex: frameIndex)
        }.value
        guard let result, !isCancelled else { return nil }
        memoryCache.store(result, key: cacheKey, frameIndex: frameIndex)
        schedulePrefetch(around: frameIndex, archive: archive)
        return result
    }

    func cancel() {
        isCancelled = true
        preparationTask?.cancel()
        refreshTask?.cancel()
        preparationTask = nil
        refreshTask = nil
        archive = nil
    }

    private func preparedArchive() async -> PlexBIFArchive? {
        if let archive {
            return archive
        }
        guard !isCancelled, !isUnavailable else { return nil }
        if let preparationTask {
            return await finishPreparation(preparationTask)
        }

        let source = self.source
        let diskCache = self.diskCache
        let cacheKey = self.cacheKey
        let intervalMilliseconds = self.intervalMilliseconds
        let task = Task<PreparedArchive?, Never> {
            await Self.loadInitialArchive(
                source: source,
                diskCache: diskCache,
                cacheKey: cacheKey,
                intervalMilliseconds: intervalMilliseconds,
            )
        }
        preparationTask = task
        return await finishPreparation(task)
    }

    private func finishPreparation(
        _ task: Task<PreparedArchive?, Never>,
    ) async -> PlexBIFArchive? {
        let prepared = await task.value
        guard !isCancelled else { return nil }
        preparationTask = nil
        guard let prepared else {
            isUnavailable = true
            return nil
        }
        archive = prepared.archive
        if prepared.shouldRevalidate {
            scheduleRefresh(metadata: prepared.metadata)
        }
        return prepared.archive
    }

    private func scheduleRefresh(metadata: PlexBIFCacheMetadata) {
        guard refreshTask == nil else { return }
        let source = self.source
        let diskCache = self.diskCache
        let cacheKey = self.cacheKey
        let intervalMilliseconds = self.intervalMilliseconds
        refreshTask = Task { [weak self] in
            let refreshed = await Self.refreshArchive(
                source: source,
                diskCache: diskCache,
                cacheKey: cacheKey,
                intervalMilliseconds: intervalMilliseconds,
                metadata: metadata,
            )
            guard let self else { return }
            await self.finishRefresh(refreshed)
        }
    }

    private func finishRefresh(_ refreshed: PlexBIFArchive?) {
        refreshTask = nil
        guard !isCancelled, let refreshed else { return }
        archive = refreshed
    }

    private func schedulePrefetch(
        around frameIndex: Int,
        archive: PlexBIFArchive,
    ) {
        let indexes = [frameIndex - 1, frameIndex + 1]
            .filter { archive.frames.indices.contains($0) }
        let memoryCache = self.memoryCache
        let cacheKey = self.cacheKey
        Task(priority: .utility) {
            for index in indexes {
                if memoryCache.thumbnail(key: cacheKey, frameIndex: index) != nil {
                    continue
                }
                let thumbnail = await Task.detached(priority: .utility) {
                    try? archive.thumbnail(frameIndex: index)
                }.value
                if let thumbnail {
                    memoryCache.store(thumbnail, key: cacheKey, frameIndex: index)
                }
            }
        }
    }

    private static func loadInitialArchive(
        source: PlexBIFSource,
        diskCache: PlexBIFDiskCache,
        cacheKey: String,
        intervalMilliseconds: Int,
    ) async -> PreparedArchive? {
        do {
            if let cached = try await diskCache.entry(for: cacheKey) {
                do {
                    let archive = try PlexBIFArchive(fileURL: cached.fileURL)
                    return PreparedArchive(
                        archive: archive,
                        metadata: cached.metadata,
                        shouldRevalidate: shouldRevalidate(cached.metadata),
                    )
                } catch {
                    await diskCache.remove(key: cacheKey)
                    await MainActor.run {
                        ErrorReporter.capture(error)
                    }
                }
            }

            let result = try await source.repository.fetch(
                partID: source.partID,
                intervalMilliseconds: intervalMilliseconds,
            )
            switch result {
            case let .downloaded(fileURL, validators):
                defer { try? FileManager.default.removeItem(at: fileURL) }
                let archive = try await diskCache.store(
                    stagedFileURL: fileURL,
                    key: cacheKey,
                    validators: validators,
                )
                let metadata = try await diskCache.entry(for: cacheKey)?.metadata
                    ?? PlexBIFCacheMetadata(
                        validators: validators,
                        lastValidatedAt: Date(),
                        lastAccessedAt: Date(),
                        byteCount: 0,
                    )
                return PreparedArchive(
                    archive: archive,
                    metadata: metadata,
                    shouldRevalidate: false,
                )
            case .notModified:
                return nil
            case .unavailable:
                return nil
            }
        } catch {
            guard !Task.isCancelled, !isCancellation(error) else { return nil }
            await reportUnexpectedLocalError(error)
            return nil
        }
    }

    private static func refreshArchive(
        source: PlexBIFSource,
        diskCache: PlexBIFDiskCache,
        cacheKey: String,
        intervalMilliseconds: Int,
        metadata: PlexBIFCacheMetadata,
    ) async -> PlexBIFArchive? {
        do {
            let validators = metadata.validators.hasValidator
                ? metadata.validators
                : nil
            let result = try await source.repository.fetch(
                partID: source.partID,
                intervalMilliseconds: intervalMilliseconds,
                validators: validators,
            )
            switch result {
            case let .downloaded(fileURL, validators):
                defer { try? FileManager.default.removeItem(at: fileURL) }
                return try await diskCache.store(
                    stagedFileURL: fileURL,
                    key: cacheKey,
                    validators: validators,
                )
            case let .notModified(validators):
                try await diskCache.markValidated(
                    key: cacheKey,
                    validators: validators,
                )
                return nil
            case .unavailable:
                return nil
            }
        } catch {
            guard !Task.isCancelled, !isCancellation(error) else { return nil }
            await reportUnexpectedLocalError(error)
            return nil
        }
    }

    private nonisolated static func shouldRevalidate(
        _ metadata: PlexBIFCacheMetadata,
    ) -> Bool {
        let maximumAge: TimeInterval = metadata.validators.hasValidator
            ? 24 * 60 * 60
            : 7 * 24 * 60 * 60
        return Date().timeIntervalSince(metadata.lastValidatedAt) >= maximumAge
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }

    private static func reportUnexpectedLocalError(_ error: Error) async {
        guard error is PlexBIFArchiveError || error is CocoaError else { return }
        await MainActor.run {
            ErrorReporter.capture(error)
        }
    }
}
