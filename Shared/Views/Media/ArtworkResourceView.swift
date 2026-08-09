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
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
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
                        height: height
                    )
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    resource = nil
                }
            }
    }
}
