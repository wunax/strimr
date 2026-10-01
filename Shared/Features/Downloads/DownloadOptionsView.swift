import Observation
import SwiftUI

@MainActor
@Observable
final class DownloadOptionsViewModel {
    let itemID: String
    let kind: MediaKind
    let services: MediaServices
    var quality: TranscodeQualityPreset
    var trackSelection: MediaTrackSelection?
    var selectedAudioID: Int?
    var selectedSubtitleID: Int?
    var isLoadingTracks = false
    var errorMessage: String?
    private(set) var versions: [MediaFileVersion] = []
    var selectedVersionID: String?
    private var representativeItemID: String?
    private var didLoadVersions = false

    /// For a season or series, versions come from a representative episode and other episodes match by signature.
    init(
        itemID: String,
        kind: MediaKind,
        services: MediaServices,
        defaultQuality: TranscodeQualityPreset,
    ) {
        self.itemID = itemID
        self.kind = kind
        self.services = services
        quality = defaultQuality
    }

    var showsVersionSelection: Bool {
        versions.count > 1
    }

    var versionLabels: [String] {
        MediaFileVersion.displayLabels(for: versions)
    }

    /// The download choice never becomes the playback preference.
    var versionRequest: MediaVersionRequest {
        guard showsVersionSelection,
              let selectedVersionID,
              let version = versions.first(where: { $0.matchesVersionID(selectedVersionID) })
        else { return .automatic }
        return .preferred(MediaVersionPreference(
            versionID: version.id,
            signature: version.signature,
            updatedAt: Date(),
        ))
    }

    var loadKey: String {
        "\(quality.rawValue)|\(selectedVersionID ?? "")"
    }

    var showsTrackSelection: Bool {
        services.provider == .jellyfin && !quality.isOriginal
    }

    var audioTracks: [MediaTrackMetadata] {
        trackSelection?.audioTracks ?? []
    }

    var subtitleTracks: [MediaTrackMetadata] {
        (trackSelection?.subtitleTracks ?? []).filter { track in
            ["srt", "subrip", "ass", "ssa", "vtt", "webvtt"].contains(track.codec.lowercased())
        }
    }

    var preference: MediaTrackPreference {
        guard showsTrackSelection else { return .serverDefault }
        let audio = audioTracks.first(where: { $0.id == selectedAudioID })
        let subtitle = subtitleTracks.first(where: { $0.id == selectedSubtitleID })
        return MediaTrackPreference(
            audioStreamIndex: audio?.sourceIndex ?? audio?.id,
            audioLanguage: audio?.language,
            audioTitle: audio?.displayTitle,
            audioCodec: audio?.codec,
            audioIsHearingImpaired: audio?.isHearingImpaired,
            audioIsCommentary: nil,
            subtitle: subtitle.map {
                .track(
                    streamIndex: $0.sourceIndex ?? $0.id ?? 0,
                    language: $0.language,
                    title: $0.displayTitle,
                    codec: $0.codec,
                    isForced: $0.isForced,
                    isHearingImpaired: $0.isHearingImpaired,
                )
            } ?? .off,
        )
    }

    func loadIfNeeded() async {
        if !didLoadVersions {
            await loadVersions()
        }
        await loadTracksIfNeeded()
    }

    private func loadVersions() async {
        do {
            let items = try await services.downloads.downloadableItems(itemID: itemID, kind: kind)
            guard let representative = items.first(where: { !$0.isFullyWatched }) ?? items.first else {
                didLoadVersions = true
                return
            }
            let selection = try await services.detail.trackSelection(itemID: representative.id, versionID: nil)
            guard !Task.isCancelled else { return }
            representativeItemID = representative.id
            versions = selection.versions
            // Start from the version playback would pick.
            let initial = MediaVersionResolver.resolve(
                services.versionRequest(for: representative),
                in: selection.versions,
            ) { versions in
                versions.first { version in selection.defaultVersionID.map(version.matchesVersionID) ?? false }
            }
            selectedVersionID = initial?.id ?? selection.versionID
            if selection.versionID == selectedVersionID {
                applyTracks(selection)
            }
            didLoadVersions = true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            didLoadVersions = true
            errorMessage = error.localizedDescription
            ErrorReporter.capture(error)
        }
    }

    private func loadTracksIfNeeded() async {
        guard showsTrackSelection, !isLoadingTracks else { return }
        guard trackSelection == nil || trackSelection?.versionID != selectedVersionID else { return }
        isLoadingTracks = true
        defer { isLoadingTracks = false }
        do {
            let selection = try await services.detail.trackSelection(
                itemID: representativeItemID ?? itemID,
                versionID: selectedVersionID,
            )
            applyTracks(selection)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
            ErrorReporter.capture(error)
        }
    }

    private func applyTracks(_ selection: MediaTrackSelection) {
        trackSelection = selection
        selectedAudioID = selection.selectedAudioTrackID ?? selection.audioTracks.first?.id
        selectedSubtitleID = selection.selectedSubtitleTrackID.flatMap { selected in
            subtitleTracks.contains(where: { $0.id == selected }) ? selected : nil
        }
    }
}

@MainActor
struct DownloadOptionsSections: View {
    @Bindable var model: DownloadOptionsViewModel

    var body: some View {
        if model.showsVersionSelection {
            Section("downloads.options.version") {
                Picker("downloads.options.version", selection: $model.selectedVersionID) {
                    ForEach(Array(zip(model.versions, model.versionLabels)), id: \.0) { version, label in
                        Text(label)
                            .tag(version.id)
                            .disabled(!version.isAvailable)
                    }
                }
            }
        }

        Section("downloads.options.quality") {
            Picker("downloads.options.quality", selection: $model.quality) {
                ForEach(TranscodeQualityPreset.displayOrder) { preset in
                    Text(preset.title).tag(preset)
                }
            }
        }

        if model.showsTrackSelection {
            Section("downloads.options.tracks") {
                if model.isLoadingTracks {
                    ProgressView()
                } else {
                    Picker("downloads.options.audio", selection: $model.selectedAudioID) {
                        ForEach(model.audioTracks) { track in
                            Text(track.displayTitle).tag(track.id)
                        }
                    }
                    Picker("downloads.options.subtitles", selection: $model.selectedSubtitleID) {
                        Text("downloads.options.subtitles.off").tag(Int?.none)
                        ForEach(model.subtitleTracks) { track in
                            Text(track.displayTitle).tag(track.id)
                        }
                    }
                }
            }
        }

        if let errorMessage = model.errorMessage {
            Section {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }
}

@MainActor
struct DownloadConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: DownloadOptionsViewModel
    let onDownload: (TranscodeQualityPreset, MediaTrackPreference, MediaVersionRequest) async -> Void
    @State private var isSubmitting = false

    init(
        itemID: String,
        kind: MediaKind,
        services: MediaServices,
        defaultQuality: TranscodeQualityPreset,
        onDownload: @escaping (TranscodeQualityPreset, MediaTrackPreference, MediaVersionRequest) async -> Void,
    ) {
        _model = State(initialValue: DownloadOptionsViewModel(
            itemID: itemID,
            kind: kind,
            services: services,
            defaultQuality: defaultQuality,
        ))
        self.onDownload = onDownload
    }

    var body: some View {
        NavigationStack {
            List {
                DownloadOptionsSections(model: model)
            }
            .navigationTitle("downloads.options.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("downloads.action") {
                        isSubmitting = true
                        Task {
                            await onDownload(model.quality, model.preference, model.versionRequest)
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || (model.showsTrackSelection && model.selectedAudioID == nil))
                }
            }
            .task(id: model.loadKey) {
                await model.loadIfNeeded()
            }
        }
    }
}
