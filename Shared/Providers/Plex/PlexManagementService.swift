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

    func searchMatches(for item: MediaItem, title: String, year: Int?) async throws -> [MatchCandidate] {
        let response = try await LibraryManagementRepository(context: context)
            .matches(ratingKey: item.id, title: title, year: year)
        let images = try ImageRepository(context: context)
        return Self.matchCandidates(from: response, currentGUID: item.guid) { path in
            images.transcodeImageURL(path: path, width: 120, height: 180)
        }
    }

    func applyMatch(_ candidate: MatchCandidate, to item: MediaItem) async throws {
        guard case let .plex(guid) = candidate.payload else { return }
        try await LibraryManagementRepository(context: context)
            .applyMatch(ratingKey: item.id, guid: guid, name: candidate.title, year: candidate.year)
    }

    var supportsUnmatch: Bool {
        true
    }

    func unmatch(itemID: String) async throws {
        try await LibraryManagementRepository(context: context).unmatch(ratingKey: itemID)
    }

    static func matchCandidates(
        from response: PlexMatchResponse,
        currentGUID: String,
        posterURL: (String) -> URL?,
    ) -> [MatchCandidate] {
        var seen = Set<String>()
        return (response.mediaContainer.searchResult ?? []).compactMap { result in
            guard !result.guid.isEmpty, seen.insert(result.guid).inserted else { return nil }
            return MatchCandidate(
                id: result.guid,
                title: result.name,
                year: result.year.flatMap { Int($0.value) },
                posterURL: result.thumb.flatMap { $0.isEmpty ? nil : posterURL($0) },
                provider: matchProvider(guid: result.guid),
                isCurrent: result.guid == currentGUID,
                payload: .plex(guid: result.guid),
            )
        }
    }

    /// The agent is the guid's scheme: `plex`, or `imdb` in `com.plexapp.agents.imdb://…`.
    static func matchProvider(guid: String) -> String? {
        guard let scheme = guid.components(separatedBy: "://").first, scheme != guid else { return nil }
        return scheme.components(separatedBy: ".").last
    }

    func supportsAdvancedSettings(for item: MediaItem) -> Bool {
        Self.supportsAdvancedSettings(for: item.type)
    }

    func advancedSettings(itemID: String) async throws -> [ItemSetting] {
        let response = try await LibraryManagementRepository(context: context).itemPreferences(ratingKey: itemID)
        return Self.itemSettings(from: response)
    }

    func updateAdvancedSetting(_ setting: ItemSetting, value: String, itemID: String) async throws {
        try await LibraryManagementRepository(context: context)
            .setItemPreference(ratingKey: itemID, id: setting.id, value: value)
    }

    /// Seasons and episodes have no settings of their own.
    static func supportsAdvancedSettings(for type: MediaKind) -> Bool {
        [.movie, .series].contains(type)
    }

    /// Settings without a list of choices, such as free text, are left out.
    static func itemSettings(from response: PlexItemPreferencesResponse) -> [ItemSetting] {
        response.settings.compactMap { preference in
            guard !preference.hidden, let label = preference.label, !label.isEmpty,
                  let enumValues = preference.enumValues
            else { return nil }
            let options = settingOptions(from: enumValues)
            guard !options.isEmpty else { return nil }
            let value = preference.value ?? ""
            return ItemSetting(
                id: preference.id,
                label: label,
                summary: preference.summary.flatMap { $0.isEmpty ? nil : $0 },
                // A value missing from the choices would leave the picker without a selection.
                value: options.contains { $0.value == value } ? value : options[0].value,
                options: options,
            )
        }
    }

    static func settingOptions(from enumValues: String) -> [ItemSetting.Option] {
        enumValues.split(separator: "|", omittingEmptySubsequences: true).map { entry in
            let parts = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let value = decoded(parts[0])
            return ItemSetting.Option(value: value, label: parts.count > 1 ? decoded(parts[1]) : value)
        }
    }

    private static func decoded(_ part: Substring) -> String {
        String(part).removingPercentEncoding ?? String(part)
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
