import Foundation
import Observation

@MainActor
@Observable
final class MetadataEditorViewModel: Identifiable {
    struct Failure: Identifiable {
        let id = UUID()
        let message: String
    }

    let item: MediaItem
    var draft: MetadataDraft?
    private(set) var original: MetadataDraft?
    private(set) var loadErrorMessage: String?
    private(set) var isSaving = false
    var failure: Failure?
    var artworkPicker: ArtworkPickerViewModel?
    /// Bumped after each change applied on the server, from the form or the artwork screen.
    private(set) var changeCount = 0
    private(set) var suggestionsByField: [MetadataField: [String]] = [:]

    @ObservationIgnored private let service: any MediaManagementService
    @ObservationIgnored private let makeArtworkPicker: (() -> ArtworkPickerViewModel?)?
    @ObservationIgnored private let onSave: (String) -> Void

    static let suggestedFields: [MetadataField] = [.genres, .labels]

    init(
        item: MediaItem,
        service: any MediaManagementService,
        makeArtworkPicker: (() -> ArtworkPickerViewModel?)? = nil,
        onSave: @escaping (String) -> Void,
    ) {
        self.item = item
        self.service = service
        self.makeArtworkPicker = makeArtworkPicker
        self.onSave = onSave
    }

    var hasChanges: Bool {
        guard let draft, let original else { return false }
        return draft.hasChanges(from: original)
    }

    var canSave: Bool {
        guard let draft, hasChanges, !isSaving else { return false }
        return !draft.value(.title).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canEditArtwork: Bool {
        makeArtworkPicker != nil
    }

    func load() async {
        guard draft == nil else { return }
        loadErrorMessage = nil
        do {
            let loaded = try await service.loadMetadataDraft(for: item)
            guard !Task.isCancelled else { return }
            original = loaded
            draft = loaded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            loadErrorMessage = message(for: error)
            return
        }
        await loadSuggestions()
    }

    /// Returns whether the changes reached the server.
    func save() async -> Bool {
        guard canSave, let draft, let original else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.saveMetadata(draft, original: original, for: item)
            self.original = draft
            changeCount += 1
            onSave(item.id)
            return true
        } catch {
            guard !error.isCancellation else { return false }
            failure = Failure(message: message(for: error))
            return false
        }
    }

    func setValue(_ value: String, for field: MetadataField) {
        draft?.setValue(value, for: field)
    }

    func toggleLock(_ field: MetadataField) {
        guard let draft else { return }
        self.draft?.setLocked(!draft.isLocked(field), for: field)
    }

    func addEntry(_ entry: String, to field: MetadataField) {
        draft?.addListEntry(entry, to: field)
    }

    func removeEntry(_ entry: String, from field: MetadataField) {
        guard let draft else { return }
        self.draft?.setList(draft.list(field).filter { $0 != entry }, for: field)
    }

    /// Server values that contain `text` and are not in the list yet.
    func suggestions(for field: MetadataField, matching text: String) -> [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let draft else { return [] }
        let current = Set(draft.list(field).map { $0.lowercased() })
        return (suggestionsByField[field] ?? [])
            .filter { !current.contains($0.lowercased()) && $0.localizedStandardContains(query) }
            .prefix(5)
            .map(\.self)
    }

    func openArtwork() {
        artworkPicker = makeArtworkPicker?()
    }

    func noteArtworkChanged() {
        changeCount += 1
    }

    /// Suggestions only help typing, so failing to list them leaves the form as it is.
    private func loadSuggestions() async {
        guard let fields = draft?.fields else { return }
        for field in Self.suggestedFields where fields.contains(field) {
            guard let values = try? await service.metadataSuggestions(for: field, item: item) else { continue }
            suggestionsByField[field] = values
        }
    }

    /// Captures unexpected failures; a refusal is the server's answer to a right lost meanwhile.
    private func message(for error: Error) -> String {
        guard !error.isManagementRefusal else { return String(localized: "media.manage.error.forbidden") }
        ErrorReporter.capture(error)
        return error.localizedDescription
    }
}
