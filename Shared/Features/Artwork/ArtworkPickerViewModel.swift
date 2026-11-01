import Foundation
import Observation

@MainActor
@Observable
final class ArtworkPickerViewModel: Identifiable {
    struct Failure: Identifiable {
        let id = UUID()
        let message: String
    }

    let item: MediaItem
    let kinds: [EditableArtworkKind]
    var selectedKind: EditableArtworkKind
    var includesAllLanguages = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The option being applied, which shows a progress over its tile.
    private(set) var applyingOptionID: String?
    private(set) var isUploading = false
    var failure: Failure?
    /// Bumped after each change applied on the server.
    private(set) var changeCount = 0

    @ObservationIgnored private let service: any MediaManagementService
    @ObservationIgnored private let onChange: (String) -> Void
    @ObservationIgnored private let language = ArtworkLanguageFilter.appLanguage
    private var optionsByKind: [EditableArtworkKind: [ArtworkOption]] = [:]

    init(
        item: MediaItem,
        kinds: [EditableArtworkKind],
        service: any MediaManagementService,
        onChange: @escaping (String) -> Void,
    ) {
        self.item = item
        self.kinds = kinds
        selectedKind = kinds.first ?? .poster
        self.service = service
        self.onChange = onChange
    }

    var isBusy: Bool {
        applyingOptionID != nil || isUploading
    }

    var hasLoadedOptions: Bool {
        optionsByKind[selectedKind] != nil
    }

    var visibleOptions: [ArtworkOption] {
        ArtworkLanguageFilter.visible(
            optionsByKind[selectedKind] ?? [],
            language: language,
            includeAllLanguages: includesAllLanguages,
        )
    }

    var hasOtherLanguages: Bool {
        ArtworkLanguageFilter.hasOtherLanguages(optionsByKind[selectedKind] ?? [], language: language)
    }

    /// Reuses the options already listed for the kind unless `force`.
    func load(force: Bool = false) async {
        let kind = selectedKind
        errorMessage = nil
        guard force || optionsByKind[kind] == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let options = try await service.artworkOptions(for: item, kind: kind)
            guard !Task.isCancelled else { return }
            optionsByKind[kind] = options
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = message(for: error)
        }
    }

    func select(_ option: ArtworkOption) async {
        guard !isBusy, !option.isSelected else { return }
        let kind = selectedKind
        applyingOptionID = option.id
        defer { applyingOptionID = nil }
        do {
            try await service.selectArtwork(option, for: item, kind: kind)
            optionsByKind[kind] = optionsByKind[kind]?.map { candidate in
                var candidate = candidate
                candidate.isSelected = candidate.id == option.id
                return candidate
            }
            changeCount += 1
            onChange(item.id)
        } catch {
            guard !error.isCancellation else { return }
            failure = Failure(message: message(for: error))
        }
    }

    func upload(_ data: Data) async {
        guard !isBusy else { return }
        let kind = selectedKind
        isUploading = true
        defer { isUploading = false }
        guard let upload = await ArtworkUpload.prepare(data, for: kind) else {
            failure = Failure(message: String(localized: "media.artwork.upload.invalidImage"))
            return
        }
        do {
            try await service.uploadArtwork(upload, for: item, kind: kind)
            changeCount += 1
            onChange(item.id)
        } catch {
            guard !error.isCancellation else { return }
            failure = Failure(message: message(for: error))
            return
        }
        // The uploaded image is now the current one, which only the server can list.
        optionsByKind[kind] = nil
        if selectedKind == kind {
            await load()
        }
    }

    /// Captures unexpected failures; a refusal is the server's answer to a right lost meanwhile.
    private func message(for error: Error) -> String {
        guard !error.isManagementRefusal else { return String(localized: "media.manage.error.forbidden") }
        ErrorReporter.capture(error)
        return error.localizedDescription
    }
}
