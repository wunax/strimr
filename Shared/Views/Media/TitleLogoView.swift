import SwiftUI

/// The title's logo when the server has one, its name otherwise. The name stays until the logo is decoded, so a
/// slow or broken logo never leaves an empty title.
struct TitleLogoView: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let media: MediaItem
    let title: String
    let logoPath: String?
    let maxSize: CGSize
    let alignment: Alignment

    @State private var loaded: (key: String, image: Image)?

    init(
        media: MediaItem,
        title: String? = nil,
        logoPath: String? = nil,
        maxSize: CGSize,
        alignment: Alignment = .bottomLeading,
    ) {
        self.media = media
        self.title = title ?? media.primaryLabel
        self.logoPath = logoPath ?? media.preferredLogoPath
        self.maxSize = maxSize
        self.alignment = alignment
    }

    var body: some View {
        ZStack(alignment: alignment) {
            if let image = currentImage {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: maxSize.width, maxHeight: maxSize.height, alignment: alignment)
                    // Some logos are dark; a soft shadow keeps them readable on dark artwork without tinting them.
                    .shadow(color: .black.opacity(0.4), radius: 8)
                    .transition(.opacity)
            } else {
                // The name takes the full width rather than the logo's box, and shrinks a little so two lines still
                // fit the height reserved for the logo.
                Text(title)
                    .font(.heroTitle)
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isHeader)
        .task(id: cacheKey) { await load() }
    }

    private var services: MediaServices? {
        registry.services(for: .playable(media), scoped: scopedServices)
    }

    private var cacheKey: String? {
        guard settingsManager.interface.showsTitleLogo, let logoPath else { return nil }
        return Self.cacheKey(path: logoPath, server: media.serverIdentifier, maxSize: maxSize)
    }

    private var currentImage: Image? {
        guard let cacheKey else { return nil }
        if let loaded, loaded.key == cacheKey {
            return loaded.image
        }
        return Self.cache[cacheKey]
    }

    private var textAlignment: TextAlignment {
        switch alignment.horizontal {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private func load() async {
        guard let cacheKey, let logoPath, currentImage == nil, let services,
              let image = await Self.loadImage(path: logoPath, services: services, maxSize: maxSize, key: cacheKey),
              !Task.isCancelled
        else { return }
        withAnimation(reduceMotion ? nil : Motion.crossfade) {
            loaded = (cacheKey, image)
        }
    }

    /// Loads the logo ahead of time, e.g. with a hero backdrop, so the title appears as a logo straight away.
    static func preload(media: MediaItem, services: MediaServices, maxSize: CGSize, logoPath: String? = nil) async {
        guard let path = logoPath ?? media.preferredLogoPath else { return }
        let key = cacheKey(path: path, server: media.serverIdentifier, maxSize: maxSize)
        guard cache[key] == nil else { return }
        _ = await loadImage(path: path, services: services, maxSize: maxSize, key: key)
    }

    @MainActor private static var cache: [String: Image] = [:]
    private static let cacheLimit = 64

    private static func cacheKey(path: String, server: String, maxSize: CGSize) -> String {
        "\(server)|\(path)|\(Int(maxSize.width))x\(Int(maxSize.height))"
    }

    private static func loadImage(
        path: String,
        services: MediaServices,
        maxSize: CGSize,
        key: String,
    ) async -> Image? {
        // Requested at twice the displayed size for Retina and 4K screens.
        guard let resource = try? await services.artwork.artwork(
            path: path,
            width: Int(maxSize.width * 2),
            height: Int(maxSize.height * 2),
        ),
            let image = await ArtworkResourceView.image(for: resource)
        else { return nil }
        if cache.count >= cacheLimit {
            cache.removeAll()
        }
        cache[key] = image
        return image
    }
}
