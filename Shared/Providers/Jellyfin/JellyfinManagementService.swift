import Foundation

@MainActor
final class JellyfinManagementService: MediaManagementService {
    private let context: JellyfinAPIContext

    init(context: JellyfinAPIContext) {
        self.context = context
    }

    var supportsAnalyze: Bool {
        false
    }

    /// Replaces the metadata but keeps the images, which is what a Plex refresh does with chosen artwork.
    func refreshMetadata(itemID: String) async throws {
        try await context.send(
            path: ["Items", itemID, "Refresh"],
            method: "POST",
            query: [
                URLQueryItem(name: "MetadataRefreshMode", value: "FullRefresh"),
                URLQueryItem(name: "ImageRefreshMode", value: "FullRefresh"),
                URLQueryItem(name: "ReplaceAllMetadata", value: "true"),
                URLQueryItem(name: "ReplaceAllImages", value: "false"),
            ],
        )
    }

    func analyze(itemID _: String) async throws {}

    var supportsLibraryTrash: Bool {
        false
    }

    func scanLibrary(id: String) async throws {
        try await refreshLibrary(id: id, mode: "Default", replaceAllMetadata: false)
    }

    func refreshLibraryMetadata(id: String) async throws {
        try await refreshLibrary(id: id, mode: "FullRefresh", replaceAllMetadata: true)
    }

    func analyzeLibrary(id _: String) async throws {}

    func emptyLibraryTrash(id _: String) async throws {}

    func artworkKinds(for item: MediaItem) -> [EditableArtworkKind] {
        Self.artworkKinds(for: item.type)
    }

    func artworkOptions(for item: MediaItem, kind: EditableArtworkKind) async throws -> [ArtworkOption] {
        let type = Self.imageType(for: kind, itemType: item.type)
        // Filtered by language in the app, so the user can show every language without asking the providers again.
        let result: JellyfinRemoteImageResult = try await context.get(
            path: ["Items", item.id, "RemoteImages"],
            query: [
                URLQueryItem(name: "Type", value: type),
                URLQueryItem(name: "IncludeAllLanguages", value: "true"),
            ],
        )
        let current: [JellyfinImageInfo] = try await context.get(path: ["Items", item.id, "Images"])
        return Self.artworkOptions(from: result.images ?? [], current: current, imageType: type)
    }

    func selectArtwork(_ option: ArtworkOption, for item: MediaItem, kind: EditableArtworkKind) async throws {
        let type = Self.imageType(for: kind, itemType: item.type)
        try await context.send(
            path: ["Items", item.id, "RemoteImages", "Download"],
            method: "POST",
            query: [
                URLQueryItem(name: "Type", value: type),
                URLQueryItem(name: "ImageUrl", value: option.source),
            ],
        )
        try await promoteLatestBackdrop(itemID: item.id, imageType: type)
    }

    /// Jellyfin reads the image from a base64 body.
    func uploadArtwork(_ upload: ArtworkUpload, for item: MediaItem, kind: EditableArtworkKind) async throws {
        let type = Self.imageType(for: kind, itemType: item.type)
        try await context.send(
            path: ["Items", item.id, "Images", type],
            method: "POST",
            body: upload.data.base64EncodedData(),
            contentType: upload.contentType,
        )
        try await promoteLatestBackdrop(itemID: item.id, imageType: type)
    }

    /// An item can have several backdrops and a new one is added last, while the app shows the first.
    private func promoteLatestBackdrop(itemID: String, imageType: String) async throws {
        guard imageType == "Backdrop" else { return }
        let images: [JellyfinImageInfo] = try await context.get(path: ["Items", itemID, "Images"])
        guard let latest = images.filter({ $0.imageType == imageType }).compactMap(\.imageIndex).max(), latest > 0
        else { return }
        try await context.send(
            path: ["Items", itemID, "Images", imageType, String(latest), "Index"],
            method: "POST",
            query: [URLQueryItem(name: "newIndex", value: "0")],
        )
    }

    static func artworkKinds(for type: MediaKind) -> [EditableArtworkKind] {
        switch type {
        case .movie, .series: [.poster, .background, .logo, .thumb, .banner]
        case .season: [.poster, .background]
        case .episode: [.thumb]
        default: []
        }
    }

    /// An episode's 16:9 image is its primary image.
    static func imageType(for kind: EditableArtworkKind, itemType: MediaKind) -> String {
        switch kind {
        case .poster: "Primary"
        case .background: "Backdrop"
        case .logo: "Logo"
        case .thumb: itemType == .episode ? "Primary" : "Thumb"
        case .banner: "Banner"
        }
    }

    /// Jellyfin does not tell which remote image is in use, so the current image is recognized by its size, and only
    /// when no other image has the same.
    static func artworkOptions(
        from images: [JellyfinRemoteImage],
        current: [JellyfinImageInfo],
        imageType: String,
    ) -> [ArtworkOption] {
        var seen = Set<String>()
        let options = images.compactMap { image -> ArtworkOption? in
            guard let source = image.url, let sourceURL = URL(string: source), seen.insert(source).inserted
            else { return nil }
            return ArtworkOption(
                id: source,
                previewURL: image.thumbnailURL.flatMap(URL.init(string:)) ?? sourceURL,
                source: source,
                provider: image.providerName,
                width: image.width,
                height: image.height,
                language: image.language,
                isSelected: false,
            )
        }
        guard let image = current.first(where: { $0.imageType == imageType && ($0.imageIndex ?? 0) == 0 }),
              let width = image.width, let height = image.height
        else { return options }
        let matches = options.indices.filter { options[$0].width == width && options[$0].height == height }
        guard matches.count == 1, let match = matches.first else { return options }
        var marked = options
        marked[match].isSelected = true
        return marked
    }

    private func refreshLibrary(id: String, mode: String, replaceAllMetadata: Bool) async throws {
        try await context.send(
            path: ["Items", id, "Refresh"],
            method: "POST",
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "MetadataRefreshMode", value: mode),
                URLQueryItem(name: "ImageRefreshMode", value: mode),
                URLQueryItem(name: "ReplaceAllMetadata", value: replaceAllMetadata ? "true" : "false"),
                URLQueryItem(name: "ReplaceAllImages", value: "false"),
            ],
        )
    }
}
