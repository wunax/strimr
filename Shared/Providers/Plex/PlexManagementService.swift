import Foundation

@MainActor
final class PlexManagementService: MediaManagementService {
    private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
    }

    var supportsAnalyze: Bool {
        true
    }

    func refreshMetadata(itemID: String) async throws {
        try await LibraryManagementRepository(context: context).refreshMetadata(ratingKey: itemID)
    }

    func analyze(itemID: String) async throws {
        try await LibraryManagementRepository(context: context).analyze(ratingKey: itemID)
    }

    var supportsLibraryTrash: Bool {
        true
    }

    func scanLibrary(id: String) async throws {
        try await LibraryManagementRepository(context: context).scanSection(sectionID: id, force: false)
    }

    func refreshLibraryMetadata(id: String) async throws {
        try await LibraryManagementRepository(context: context).scanSection(sectionID: id, force: true)
    }

    func analyzeLibrary(id: String) async throws {
        try await LibraryManagementRepository(context: context).analyzeSection(sectionID: id)
    }

    func emptyLibraryTrash(id: String) async throws {
        try await LibraryManagementRepository(context: context).emptySectionTrash(sectionID: id)
    }

    func artworkKinds(for item: MediaItem) -> [EditableArtworkKind] {
        Self.artworkKinds(for: item.type)
    }

    func artworkOptions(for item: MediaItem, kind: EditableArtworkKind) async throws -> [ArtworkOption] {
        guard let element = Self.artworkElement(for: kind) else { return [] }
        let response = try await LibraryManagementRepository(context: context)
            .artwork(ratingKey: item.id, element: element)
        let images = try ImageRepository(context: context)
        let size = Self.previewSize(for: kind)
        return Self.artworkOptions(from: response) { path in
            images.transcodeImageURL(
                path: path,
                width: size.width,
                height: size.height,
                format: kind == .logo ? "png" : nil,
            )
        }
    }

    func selectArtwork(_ option: ArtworkOption, for item: MediaItem, kind: EditableArtworkKind) async throws {
        guard let element = Self.artworkElement(for: kind) else { return }
        try await LibraryManagementRepository(context: context)
            .selectArtwork(ratingKey: item.id, element: element, url: option.source)
    }

    func uploadArtwork(_ upload: ArtworkUpload, for item: MediaItem, kind: EditableArtworkKind) async throws {
        guard let element = Self.artworkElement(for: kind) else { return }
        try await LibraryManagementRepository(context: context).uploadArtwork(
            ratingKey: item.id,
            element: element,
            data: upload.data,
            contentType: upload.contentType,
        )
    }

    func deletionImpact(of item: MediaItem) async throws -> MediaDeletionImpact {
        let response = try await MetadataRepository(context: context).getMetadata(ratingKey: item.id)
        guard let metadata = response.mediaContainer.metadata?.first else { throw PlexAPIError.invalidResponse }
        return Self.deletionImpact(of: metadata)
    }

    func delete(_ item: MediaItem) async throws {
        try await LibraryManagementRepository(context: context).deleteMetadata(ratingKey: item.id)
    }

    static func deletionImpact(of item: PlexItem) -> MediaDeletionImpact {
        switch item.type {
        case .show, .season:
            return .episodes(count: item.leafCount ?? 0)
        default:
            let parts = (item.media ?? []).flatMap(\.parts)
            let sizes = parts.compactMap(\.size)
            return .files(count: parts.count, totalSize: sizes.isEmpty ? nil : sizes.reduce(0, +))
        }
    }

    /// An episode has a single 16:9 image, which Plex stores as its poster.
    static func artworkKinds(for type: MediaKind) -> [EditableArtworkKind] {
        switch type {
        case .movie, .series: [.poster, .background, .logo]
        case .season: [.poster, .background]
        case .episode: [.thumb]
        default: []
        }
    }

    static func artworkElement(for kind: EditableArtworkKind) -> String? {
        switch kind {
        case .poster, .thumb: "poster"
        case .background: "art"
        case .logo: "clearLogo"
        case .banner: nil
        }
    }

    static func artworkOptions(
        from response: PlexArtworkResponse,
        previewURL: (String) -> URL?,
    ) -> [ArtworkOption] {
        (response.mediaContainer.metadata ?? []).compactMap { artwork in
            guard let preview = previewURL(artwork.thumb ?? artwork.key) else { return nil }
            return ArtworkOption(
                id: artwork.key,
                previewURL: preview,
                source: artwork.ratingKey?.value ?? artwork.key,
                provider: artwork.provider,
                width: nil,
                height: nil,
                language: nil,
                isSelected: artwork.selected?.value == true,
            )
        }
    }

    private static func previewSize(for kind: EditableArtworkKind) -> (width: Int, height: Int) {
        kind == .poster ? (300, 450) : (480, 270)
    }
}
