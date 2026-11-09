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
            let year = (result["ProductionYear"] as? NSNumber)?.intValue
            let ids = providerIDs.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            let fallback = [name, year.map(String.init) ?? ""]
            let id = ([provider ?? ""] + (ids.isEmpty ? fallback : ids)).joined(separator: "|")
            guard seen.insert(id).inserted else { return nil }
            return try MatchCandidate(
                id: id,
                title: name,
                year: year,
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

    func editableMetadataFields(for item: MediaItem) -> [MetadataField] {
        MetadataField.editableFields(for: item.type)
    }

    func loadMetadataDraft(for item: MediaItem) async throws -> MetadataDraft {
        guard let userID = context.connection?.userID else { throw JellyfinAPIError.authenticationRequired }
        let data = try await context.rawData(path: ["Users", userID, "Items", item.id])
        let editor: JellyfinMetadataEditorInfo = try await context.get(path: ["Items", item.id, "MetadataEditor"])
        guard let draft = Self.metadataDraft(
            from: data,
            fields: editableMetadataFields(for: item),
            contentRatingOptions: (editor.parentalRatingOptions ?? []).compactMap(\.name),
        ) else { throw JellyfinAPIError.invalidResponse }
        return draft
    }

    func saveMetadata(_ draft: MetadataDraft, original: MetadataDraft, for item: MediaItem) async throws {
        guard case let .jellyfin(data) = draft.payload,
              let dto = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw JellyfinAPIError.invalidResponse }
        let updated = Self.updatedItem(dto, draft: draft, original: original)
        try await context.send(
            path: ["Items", item.id],
            method: "POST",
            body: JSONSerialization.data(withJSONObject: updated),
        )
    }

    func metadataSuggestions(for field: MetadataField, item _: MediaItem) async throws -> [String] {
        guard let key = Self.suggestionKey(for: field), let userID = context.connection?.userID else { return [] }
        let filters: JellyfinItemFilters = try await context.get(
            path: ["Items", "Filters"],
            query: [URLQueryItem(name: "UserId", value: userID)],
        )
        return (key == "Genres" ? filters.genres : filters.tags) ?? []
    }

    func supportsAdvancedSettings(for _: MediaItem) -> Bool {
        false
    }

    func advancedSettings(itemID _: String) async throws -> [ItemSetting] {
        []
    }

    func updateAdvancedSetting(_: ItemSetting, value _: String, itemID _: String) async throws {}

    private static func suggestionKey(for field: MetadataField) -> String? {
        switch field {
        case .genres: "Genres"
        case .labels: "Tags"
        default: nil
        }
    }

    /// Jellyfin has no lock for the sort title, the original title, the date and the tagline, and locks directors
    /// and writers together as the cast.
    nonisolated static func lockName(for field: MetadataField) -> String? {
        switch field {
        case .title: "Name"
        case .contentRating: "OfficialRating"
        case .studio: "Studios"
        case .summary: "Overview"
        case .genres: "Genres"
        case .labels: "Tags"
        case .directors, .writers: "Cast"
        case .countries: "ProductionLocations"
        case .sortTitle, .originalTitle, .releaseDate, .tagline: nil
        }
    }

    private nonisolated static func personType(for field: MetadataField) -> String? {
        switch field {
        case .directors: "Director"
        case .writers: "Writer"
        default: nil
        }
    }

    nonisolated static func metadataDraft(
        from data: Data,
        fields: [MetadataField],
        contentRatingOptions: [String],
    ) -> MetadataDraft? {
        guard let dto = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let people = dto["People"] as? [[String: Any]] ?? []
        func names(_ value: Any?) -> [String] {
            (value as? [[String: Any]] ?? []).compactMap { $0["Name"] as? String }
        }
        func peopleNames(_ type: String) -> [String] {
            people.filter { ($0["Type"] as? String)?.caseInsensitiveCompare(type) == .orderedSame }
                .compactMap { $0["Name"] as? String }
        }
        let values: [MetadataField: String] = [
            .title: dto["Name"] as? String,
            .sortTitle: dto["ForcedSortName"] as? String,
            .originalTitle: dto["OriginalTitle"] as? String,
            .releaseDate: (dto["PremiereDate"] as? String).map { String($0.prefix(10)) },
            .contentRating: dto["OfficialRating"] as? String,
            .studio: names(dto["Studios"]).first,
            .tagline: (dto["Taglines"] as? [String])?.first,
            .summary: dto["Overview"] as? String,
        ].compactMapValues(\.self)
        let lists: [MetadataField: [String]] = [
            .genres: dto["Genres"] as? [String] ?? [],
            .labels: dto["Tags"] as? [String] ?? [],
            .directors: peopleNames("Director"),
            .writers: peopleNames("Writer"),
            .countries: dto["ProductionLocations"] as? [String] ?? [],
        ]
        let lockNames = Set(dto["LockedFields"] as? [String] ?? [])
        let lockable = fields.filter { lockName(for: $0) != nil }
        return MetadataDraft(
            fields: fields,
            values: values,
            lists: lists,
            lockedFields: Set(lockable.filter { lockName(for: $0).map(lockNames.contains) == true }),
            lockableFields: Set(lockable),
            sharedLocks: [[.directors, .writers]],
            contentRatingOptions: contentRatingOptions,
            payload: .jellyfin(item: data),
        )
    }

    /// Changes only the edited keys of the item Jellyfin sent, since it clears whatever is missing from the body.
    nonisolated static func updatedItem(
        _ dto: [String: Any],
        draft: MetadataDraft,
        original: MetadataDraft,
    ) -> [String: Any] {
        var item = dto
        item.removeValue(forKey: "Trickplay")
        func text(_ field: MetadataField) -> Any {
            let value = draft.value(field).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? NSNull() : value
        }
        for field in draft.changedFields(from: original) {
            switch field {
            case .title: item["Name"] = draft.value(.title).trimmingCharacters(in: .whitespacesAndNewlines)
            case .sortTitle: item["ForcedSortName"] = text(field)
            case .originalTitle: item["OriginalTitle"] = text(field)
            case .contentRating: item["OfficialRating"] = text(field)
            case .summary: item["Overview"] = text(field)
            case .releaseDate:
                let value = draft.value(field)
                if MetadataDate.date(from: value) != nil {
                    // Keeps the time of day Jellyfin stored, which it reads back as is.
                    let previous = dto["PremiereDate"] as? String
                    let time = previous.flatMap { date in date.firstIndex(of: "T").map { String(date[$0...]) } }
                    item["PremiereDate"] = value + (time ?? "T00:00:00.0000000Z")
                    item["ProductionYear"] = Int(value.prefix(4))
                } else {
                    item["PremiereDate"] = NSNull()
                    item["ProductionYear"] = NSNull()
                }
            case .studio:
                let others = Array((dto["Studios"] as? [[String: Any]] ?? []).dropFirst())
                let name = draft.value(field).trimmingCharacters(in: .whitespacesAndNewlines)
                item["Studios"] = name.isEmpty ? others : [["Name": name]] + others
            case .tagline:
                let others = Array((dto["Taglines"] as? [String] ?? []).dropFirst())
                let tagline = draft.value(field).trimmingCharacters(in: .whitespacesAndNewlines)
                item["Taglines"] = tagline.isEmpty ? others : [tagline] + others
            case .genres: item["Genres"] = draft.list(field)
            case .labels: item["Tags"] = draft.list(field)
            case .countries: item["ProductionLocations"] = draft.list(field)
            case .directors, .writers:
                guard let type = personType(for: field) else { continue }
                item["People"] = replacingPeople(
                    item["People"] as? [[String: Any]] ?? [],
                    type: type,
                    names: draft.list(field),
                )
            }
        }
        var lockNames = (dto["LockedFields"] as? [String] ?? []).filter { name in
            !draft.lockableFields.contains { lockName(for: $0) == name }
        }
        for field in draft.fields where draft.isLocked(field) {
            if let name = lockName(for: field), !lockNames.contains(name) {
                lockNames.append(name)
            }
        }
        item["LockedFields"] = lockNames
        return item
    }

    /// Keeps the people of other types, and the details (id, image) of those still named.
    private nonisolated static func replacingPeople(
        _ people: [[String: Any]],
        type: String,
        names: [String],
    ) -> [[String: Any]] {
        func isOfType(_ person: [String: Any]) -> Bool {
            (person["Type"] as? String)?.caseInsensitiveCompare(type) == .orderedSame
        }
        var existing = people.filter(isOfType)
        let kept = names.map { name -> [String: Any] in
            if let index = existing.firstIndex(where: {
                ($0["Name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return existing.remove(at: index)
            }
            return ["Name": name, "Type": type]
        }
        return people.filter { !isOfType($0) } + kept
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
