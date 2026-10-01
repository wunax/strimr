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
            if let image = platformImage(data: data) {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Color.gray.opacity(0.1)
    }

    private func platformImage(data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            UIImage(data: data).map(Image.init(uiImage:))
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
                Color.gray.opacity(0.1)
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

    private func load() async {
        guard currentImage == nil else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(status) {
                throw URLError(.badServerResponse)
            }
            guard let image = PlatformImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            Self.cache.setObject(image, forKey: url as NSURL)
            loaded = (url, image)
            failedURL = nil
        } catch {
            // Left untouched on cancellation so the next appearance retries.
            guard !Task.isCancelled, !error.isCancellation else { return }
            failedURL = url
        }
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
