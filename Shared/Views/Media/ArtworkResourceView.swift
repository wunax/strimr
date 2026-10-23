import ImageIO
import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct ArtworkResourceView: View {
    let resource: ArtworkResource?

    var body: some View {
        switch resource {
        case let .url(url):
            RemoteArtworkImage(url: url)
        case let .data(data):
            DataArtworkImage(data: data)
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Color.surfaceSubtle
    }

    /// Warms the image caches so a view created afterwards renders the artwork on its first frame.
    static func preload(_ resource: ArtworkResource) async {
        _ = await image(for: resource)
    }

    /// The decoded artwork, for callers that lay it out themselves; nil when it cannot be loaded.
    static func image(for resource: ArtworkResource) async -> Image? {
        let image: PlatformImage? = switch resource {
        case let .url(url):
            try? await RemoteArtworkImage.image(for: url)
        case let .data(data):
            await DataArtworkImage.image(for: data)
        }
        return image.map(Image.init(platformImage:))
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}

/// `UIImage(data:)` in `body` decoded the image lazily on the main actor at every render, which stalled tvOS focus
/// moves on Jellyfin rows (raw artwork data, unlike Plex URLs). Decoding now happens once, off the main actor.
private struct DataArtworkImage: View {
    /// `NSData` hashes only its first bytes and compares contents on collision, so lookups stay cheap.
    private static let cache: NSCache<NSData, PlatformImage> = {
        let cache = NSCache<NSData, PlatformImage>()
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    let data: Data
    @State private var loaded: (data: Data, image: PlatformImage)?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = currentImage {
                platformImage(image).resizable().scaledToFill()
            } else if failed {
                Color.surfaceSubtle
            } else {
                Color.clear
            }
        }
        .task(id: data) { await load() }
    }

    private var currentImage: PlatformImage? {
        if let loaded, loaded.data == data {
            return loaded.image
        }
        return Self.cache.object(forKey: data as NSData)
    }

    /// Always ends in a state change: an image found in the cache after a cancelled load would otherwise never
    /// trigger a render, and the card stayed blank.
    private func load() async {
        guard loaded?.data != data else { return }
        failed = false
        guard let image = await Self.image(for: data) else {
            guard !Task.isCancelled else { return }
            failed = true
            return
        }
        loaded = (data, image)
    }

    static func image(for data: Data) async -> PlatformImage? {
        if let cached = cache.object(forKey: data as NSData) {
            return cached
        }
        guard let (image, cost) = await decode(data) else { return nil }
        cache.setObject(image, forKey: data as NSData, cost: cost)
        return image
    }

    @concurrent
    private nonisolated static func decode(_ data: Data) async -> (PlatformImage, cost: Int)? {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options)
        else { return nil }
        let cost = cgImage.bytesPerRow * cgImage.height
        #if os(macOS)
            return (NSImage(cgImage: cgImage, size: .zero), cost)
        #else
            return (UIImage(cgImage: cgImage), cost)
        #endif
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(macOS)
            Image(nsImage: image)
        #else
            Image(uiImage: image)
        #endif
    }
}

/// Replaces `AsyncImage`, which stays stuck on `.failure` when its load is cancelled (view rebuilt or hidden
/// mid-load, e.g. a hub refreshed behind the player) and never retries.
private struct RemoteArtworkImage: View {
    private static let cache: NSCache<NSURL, PlatformImage> = {
        let cache = NSCache<NSURL, PlatformImage>()
        cache.countLimit = 300
        return cache
    }()

    let url: URL
    @State private var loaded: (url: URL, image: PlatformImage)?
    @State private var failedURL: URL?

    var body: some View {
        Group {
            if let image = currentImage {
                platformImage(image).resizable().scaledToFill()
            } else if failedURL == url {
                Color.surfaceSubtle
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) { await load() }
    }

    private var currentImage: PlatformImage? {
        if let loaded, loaded.url == url {
            return loaded.image
        }
        return Self.cache.object(forKey: url as NSURL)
    }

    /// Like `DataArtworkImage`, stores a cached image in the state so the view renders it.
    private func load() async {
        guard loaded?.url != url else { return }
        do {
            let image = try await Self.image(for: url)
            loaded = (url, image)
            failedURL = nil
        } catch {
            // Left untouched on cancellation so the next appearance retries.
            guard !Task.isCancelled, !error.isCancellation else { return }
            failedURL = url
        }
    }

    static func image(for url: URL) async throws -> PlatformImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(status) {
            throw URLError(.badServerResponse)
        }
        guard let image = PlatformImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(macOS)
            Image(nsImage: image)
        #else
            Image(uiImage: image)
        #endif
    }
}

#if os(macOS)
    private typealias PlatformImage = NSImage
#else
    private typealias PlatformImage = UIImage
#endif

struct ArtworkPathView: View {
    @Environment(MediaServices.self) private var services
    let path: String?
    let width: Int?
    let height: Int?
    @State private var resource: ArtworkResource?

    var body: some View {
        ArtworkResourceView(resource: resource)
            .task(id: path) {
                guard let path else {
                    resource = nil
                    return
                }
                do {
                    resource = try await services.artwork.artwork(
                        path: path,
                        width: width,
                        height: height,
                    )
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    resource = nil
                }
            }
    }
}
