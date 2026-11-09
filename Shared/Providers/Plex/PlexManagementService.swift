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

    func editableMetadataFields(for item: MediaItem) -> [MetadataField] {
        Self.metadataType(for: item.type) == nil ? [] : MetadataField.editableFields(for: item.type)
    }

    func loadMetadataDraft(for item: MediaItem) async throws -> MetadataDraft {
        let response = try await LibraryManagementRepository(context: context).editableMetadata(ratingKey: item.id)
        guard let metadata = response.mediaContainer.metadata?.first,
              let sectionID = metadata.librarySectionID?.value ?? response.mediaContainer.librarySectionID?.value
              ?? item.librarySectionID,
              let type = Self.metadataType(for: item.type)
        else { throw PlexAPIError.invalidResponse }
        return Self.metadataDraft(
            from: metadata,
            fields: MetadataField.editableFields(for: item.type),
            sectionID: sectionID,
            type: type,
        )
    }

    func saveMetadata(_ draft: MetadataDraft, original: MetadataDraft, for item: MediaItem) async throws {
        guard case let .plex(sectionID, type) = draft.payload else { return }
        let repository = try LibraryManagementRepository(context: context)
        for queryItems in Self.metadataUpdates(draft, original: original, itemID: item.id, type: type) {
            try await repository.updateMetadata(sectionID: sectionID, queryItems: queryItems)
        }
    }

    func metadataSuggestions(for field: MetadataField, item: MediaItem) async throws -> [String] {
        guard [.genres, .labels].contains(field), let tag = Self.metadataKey(for: field),
              let sectionID = item.librarySectionID
        else { return [] }
        let response = try await LibraryManagementRepository(context: context)
            .tagValues(sectionID: sectionID, tag: tag)
        return (response.mediaContainer.directory ?? []).map(\.title)
    }

    static func metadataType(for type: MediaKind) -> Int? {
        switch type {
        case .movie: 1
        case .series: 2
        case .episode: 4
        default: nil
        }
    }

    static func metadataKey(for field: MetadataField) -> String? {
        switch field {
        case .title: "title"
        case .sortTitle: "titleSort"
        case .originalTitle: "originalTitle"
        case .releaseDate: "originallyAvailableAt"
        case .contentRating: "contentRating"
        case .studio: "studio"
        case .tagline: "tagline"
        case .summary: "summary"
        case .genres: "genre"
        case .labels: "label"
        case .directors: "director"
        case .writers: "writer"
        case .countries: "country"
        }
    }

    static func metadataDraft(
        from metadata: PlexEditableMetadata,
        fields: [MetadataField],
        sectionID: String,
        type: Int,
    ) -> MetadataDraft {
        let lockedKeys = Set((metadata.fields ?? []).filter { $0.locked?.value == true }.map(\.name))
        let values: [MetadataField: String] = [
            .title: metadata.title,
            .sortTitle: metadata.titleSort,
            .originalTitle: metadata.originalTitle,
            .releaseDate: metadata.originallyAvailableAt.map { String($0.prefix(10)) },
            .contentRating: metadata.contentRating,
            .studio: metadata.studio,
            .tagline: metadata.tagline,
            .summary: metadata.summary,
        ].compactMapValues(\.self)
        let lists: [MetadataField: [String]] = [
            .genres: metadata.genres,
            .labels: metadata.labels,
            .directors: metadata.directors,
            .writers: metadata.writers,
            .countries: metadata.countries,
        ].compactMapValues { $0?.map(\.tag) }
        return MetadataDraft(
            fields: fields,
            values: values,
            lists: lists,
            lockedFields: Set(fields.filter { metadataKey(for: $0).map(lockedKeys.contains) == true }),
            lockableFields: Set(fields),
            payload: .plex(sectionID: sectionID, type: type),
        )
    }

    /// The edit requests, usually one. `tag.tag-` removes a comma-separated list with no escape, so a removed tag
    /// containing a comma gets a request of its own; each request restates the kept tags, so the order is irrelevant.
    static func metadataUpdates(
        _ draft: MetadataDraft,
        original: MetadataDraft,
        itemID: String,
        type: Int,
    ) -> [[URLQueryItem]] {
        let base = [URLQueryItem(name: "type", value: String(type)), URLQueryItem(name: "id", value: itemID)]
        var main = base
        var separateRemovals: [[URLQueryItem]] = []
        func lock(_ key: String, _ field: MetadataField) -> URLQueryItem {
            URLQueryItem(name: "\(key).locked", value: draft.isLocked(field) ? "1" : "0")
        }
        for field in draft.changedFields(from: original) {
            guard let key = metadataKey(for: field) else { continue }
            guard field.isList else {
                main += [URLQueryItem(name: "\(key).value", value: draft.value(field)), lock(key, field)]
                continue
            }
            let current = draft.list(field)
            let kept = current.enumerated()
                .map { URLQueryItem(name: "\(key)[\($0.offset)].tag.tag", value: $0.element) }
            let removed = original.list(field).filter { !current.contains($0) }
            main += kept
            if removed.contains(where: { $0.contains(",") }) {
                separateRemovals += removed.map {
                    base + kept + [URLQueryItem(name: "\(key)[].tag.tag-", value: $0), lock(key, field)]
                }
            } else if !removed.isEmpty {
                main.append(URLQueryItem(name: "\(key)[].tag.tag-", value: removed.joined(separator: ",")))
            }
            main.append(lock(key, field))
        }
        for field in draft.lockChangedFields(from: original) {
            guard let key = metadataKey(for: field) else { continue }
            main.append(lock(key, field))
        }
        return [main] + separateRemovals
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
            var options = settingOptions(from: enumValues)
            guard !options.isEmpty else { return nil }
            let value = preference.value ?? ""
            // Shows a value missing from the choices as it is, so choosing any listed one still sends it.
            if !options.contains(where: { $0.value == value }) {
                options.insert(ItemSetting.Option(value: value, label: value), at: 0)
            }
            return ItemSetting(
                id: preference.id,
                label: label,
                summary: preference.summary.flatMap { $0.isEmpty ? nil : $0 },
                value: value,
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
