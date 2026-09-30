import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Artwork loader used in place of `AsyncImage` for media artwork: memory → pinned disk → cache disk → network.
/// Keys are built from the owner, the tokenless artwork path and a size bucket, never from URLs (Plex URLs carry
/// the token). Images are stored resized to the displayed size.
@MainActor
final class CachedArtworkService: MediaArtworkService {
    private static let memoryCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static let sizeBuckets = [360, 720, 1400]

    private let base: any MediaArtworkService
    private let owner: MediaOwner
    private let store: OfflineStore
    private let coordinator: OfflineCoordinator
    private var inFlight: [String: Task<Data?, Error>] = [:]

    init(base: any MediaArtworkService, owner: MediaOwner, store: OfflineStore, coordinator: OfflineCoordinator) {
        self.base = base
        self.owner = owner
        self.store = store
        self.coordinator = coordinator
    }

    /// Always `nil`: views then fall back to `artwork(path:)`, which goes through the cache.
    func artworkURL(path _: String?, width _: Int?, height _: Int?) -> URL? {
        nil
    }

    func artwork(
        for media: MediaDisplayItem,
        kind: MediaImageViewModel.ArtworkKind,
        width: Int?,
        height: Int?,
    ) async throws -> ArtworkResource? {
        try await artwork(
            path: kind == .thumb ? media.preferredThumbPath : media.preferredArtPath,
            width: width,
            height: height,
        )
    }

    func artwork(path: String?, width: Int?, height: Int?) async throws -> ArtworkResource? {
        guard let path else { return nil }
        if let downloadID = OfflineArtworkPath.downloadID(fromPosterPath: path) {
            return (try? Data(contentsOf: DownloadManager.posterFileURL(downloadID: downloadID)))
                .map(ArtworkResource.data)
        }
        return try await data(path: path, width: width, height: height, pinned: false).map(ArtworkResource.data)
    }

    /// Downloads artwork into the pinned store and returns its key, for downloads.
    func pin(path: String?, width: Int?, height: Int?) async -> String? {
        guard let path, OfflineArtworkPath.downloadID(fromPosterPath: path) == nil else { return nil }
        let key = Self.key(path: path, width: width, height: height)
        do {
            _ = try await data(path: path, width: width, height: height, pinned: true)
            return key
        } catch {
            return nil
        }
    }

    private func data(path: String, width: Int?, height: Int?, pinned: Bool) async throws -> Data? {
        let key = Self.key(path: path, width: width, height: height)
        let memoryKey = "\(owner.id)|\(key)" as NSString
        if !pinned, let cached = Self.memoryCache.object(forKey: memoryKey) {
            return cached as Data
        }
        if let url = store.artworkFileURL(key: key, owner: owner), let data = try? Data(contentsOf: url) {
            if pinned, !store.isArtworkPinned(key: key, owner: owner) {
                store.storeArtwork(data, key: key, owner: owner, width: width, height: height, pinned: true)
            }
            Self.memoryCache.setObject(data as NSData, forKey: memoryKey, cost: data.count)
            return data
        }
        if coordinator.isUnreachable(owner.server) {
            // Offline: any other size of the same artwork is better than nothing.
            if let url = store.artworkFileURL(pathPrefix: Self.pathPrefix(path), owner: owner),
               let data = try? Data(contentsOf: url)
            {
                return data
            }
            throw MediaUnavailableOffline()
        }

        let task: Task<Data?, Error>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task { [base] in
                guard let resource = try await base.artwork(path: path, width: width, height: height) else {
                    return nil
                }
                let raw: Data = switch resource {
                case let .data(value):
                    value
                case let .url(url):
                    try await Self.download(url)
                }
                return await Self.resized(raw, maximumPixelSize: Self.bucket(width: width, height: height))
            }
            inFlight[key] = task
        }
        defer { inFlight[key] = nil }

        do {
            guard let data = try await task.value, !data.isEmpty else { return nil }
            coordinator.reportSuccess(on: owner.server)
            store.storeArtwork(data, key: key, owner: owner, width: width, height: height, pinned: pinned)
            Self.memoryCache.setObject(data as NSData, forKey: memoryKey, cost: data.count)
            return data
        } catch {
            if error.isTransportFailure {
                coordinator.reportTransportFailure(on: owner.server)
                if let url = store.artworkFileURL(pathPrefix: Self.pathPrefix(path), owner: owner),
                   let data = try? Data(contentsOf: url)
                {
                    return data
                }
            }
            throw error
        }
    }

    private static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(status) {
            throw PlexAPIError.requestFailed(statusCode: status)
        }
        return data
    }

    static func key(path: String, width: Int?, height: Int?) -> String {
        pathPrefix(path) + String(bucket(width: width, height: height))
    }

    private static func pathPrefix(_ path: String) -> String {
        path + "|"
    }

    private static func bucket(width: Int?, height: Int?) -> Int {
        let requested = max(width ?? 0, height ?? 0)
        guard requested > 0 else { return 720 }
        return sizeBuckets.first { $0 >= requested } ?? sizeBuckets[sizeBuckets.count - 1]
    }

    /// Downscales to the displayed size and re-encodes as JPEG; originals can be 10 to 40 times larger.
    @concurrent
    private nonisolated static func resized(_ data: Data, maximumPixelSize: Int) async -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return data }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return data }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary,
        )
        guard CGImageDestinationFinalize(destination) else { return data }
        return output.length < data.count ? output as Data : data
    }
}
