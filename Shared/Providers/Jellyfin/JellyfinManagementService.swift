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

    /// Asks every provider, which can take longer than a usual request.
    func searchMatches(for item: MediaItem, title: String, year: Int?) async throws -> [MatchCandidate] {
        guard let searchType = Self.remoteSearchType(for: item.type) else { return [] }
        var searchInfo: [String: Any] = ["Name": title]
        if let year {
            searchInfo["Year"] = year
        }
        let body = try JSONSerialization.data(withJSONObject: ["ItemId": item.id, "SearchInfo": searchInfo])
        let data = try await context.rawData(
            path: ["Items", "RemoteSearch", searchType],
            method: "POST",
            body: body,
            timeout: Self.remoteSearchTimeout,
        )
        return try Self.matchCandidates(from: data, current: item.externalIDs)
    }

    /// The server answers once it has refreshed the item with the new match.
    func applyMatch(_ candidate: MatchCandidate, to item: MediaItem) async throws {
        guard case let .jellyfin(result) = candidate.payload else { return }
        try await context.send(
            path: ["Items", "RemoteSearch", "Apply", item.id],
            method: "POST",
            query: [URLQueryItem(name: "ReplaceAllImages", value: "true")],
            body: result,
            timeout: Self.remoteSearchTimeout,
        )
    }

    var supportsUnmatch: Bool {
        false
    }

    func unmatch(itemID _: String) async throws {}

    static let remoteSearchTimeout: TimeInterval = 120

    static func remoteSearchType(for type: MediaKind) -> String? {
        switch type {
        case .movie: "Movie"
        case .series: "Series"
        default: nil
        }
    }

    /// Each provider answers separately, so a title can come back once per provider.
    static func matchCandidates(from data: Data, current: ExternalIDs) throws -> [MatchCandidate] {
        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw JellyfinAPIError.invalidResponse
        }
        var seen = Set<String>()
        return try results.compactMap { result in
            guard let name = result["Name"] as? String, !name.isEmpty else { return nil }
            let provider = result["SearchProviderName"] as? String
            let providerIDs = (result["ProviderIds"] as? [String: Any] ?? [:])
                .compactMapValues { value in (value as? String) ?? (value as? NSNumber)?.stringValue }
            let ids = providerIDs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            let id = ([provider ?? ""] + (ids.isEmpty ? [name] : ids)).joined(separator: "|")
            guard seen.insert(id).inserted else { return nil }
            return try MatchCandidate(
                id: id,
                title: name,
                year: (result["ProductionYear"] as? NSNumber)?.intValue,
                posterURL: (result["ImageUrl"] as? String).flatMap(URL.init(string:)),
                provider: provider,
                isCurrent: ExternalIDs(providerIDs: providerIDs).sharesID(with: current),
                payload: .jellyfin(JSONSerialization.data(withJSONObject: result)),
            )
        }
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

    /// `CanDelete` is only trustworthy on a single item, so it is read before each deletion.
    func deletionImpact(of item: MediaItem) async throws -> MediaDeletionImpact {
        let details = try await JellyfinCatalogService(context: context).item(id: item.id)
        guard details.canDelete == true else { throw JellyfinAPIError.permissionDenied }
        guard [.series, .season].contains(item.type) else { return Self.deletionImpact(of: details, episodeCount: nil) }
        let episodes: JellyfinQueryResult<JellyfinItem> = try await context.get(
            path: ["Items"],
            query: [
                URLQueryItem(name: "ParentId", value: item.id),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Episode"),
                URLQueryItem(name: "IsMissing", value: "false"),
                URLQueryItem(name: "Limit", value: "0"),
            ],
        )
        return Self.deletionImpact(of: details, episodeCount: episodes.totalRecordCount)
    }

    func delete(_ item: MediaItem) async throws {
        try await context.send(path: ["Items", item.id], method: "DELETE")
    }

    /// The versions of a movie are its media sources, all deleted with it.
    static func deletionImpact(of item: JellyfinItem, episodeCount: Int?) -> MediaDeletionImpact {
        switch item.type?.lowercased() {
        case "series", "season":
            return .episodes(count: episodeCount ?? item.recursiveItemCount ?? 0)
        default:
            let sources = item.mediaSources ?? []
            let sizes = sources.compactMap(\.size)
            return .files(count: max(sources.count, 1), totalSize: sizes.isEmpty ? nil : sizes.reduce(0, +))
        }
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
