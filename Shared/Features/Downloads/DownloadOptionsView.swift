import Observation
import SwiftUI

@MainActor
@Observable
final class DownloadOptionsViewModel {
    let itemID: String
    let services: MediaServices
    var quality: TranscodeQualityPreset
    var trackSelection: MediaTrackSelection?
    var selectedAudioID: Int?
    var selectedSubtitleID: Int?
    var isLoadingTracks = false
    var errorMessage: String?

    init(itemID: String, services: MediaServices, defaultQuality: TranscodeQualityPreset) {
        self.itemID = itemID
        self.services = services
        quality = defaultQuality
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

    var preference: MediaDownloadTrackPreference {
        guard showsTrackSelection else { return .serverDefault }
        let audio = audioTracks.first(where: { $0.id == selectedAudioID })
        let subtitle = subtitleTracks.first(where: { $0.id == selectedSubtitleID })
        return MediaDownloadTrackPreference(
            audioStreamIndex: audio?.sourceIndex ?? audio?.id,
            audioLanguage: audio?.language,
            audioTitle: audio?.displayTitle,
            subtitle: subtitle.map {
                .track(
                    streamIndex: $0.sourceIndex ?? $0.id ?? 0,
                    language: $0.language,
                    title: $0.displayTitle,
                    codec: $0.codec,
                    isForced: $0.isForced,
                )
            } ?? .off,
        )
    }

    func loadTracksIfNeeded() async {
        guard showsTrackSelection, trackSelection == nil, !isLoadingTracks else { return }
        isLoadingTracks = true
        defer { isLoadingTracks = false }
        do {
            let selection = try await services.detail.trackSelection(itemID: itemID)
            trackSelection = selection
            selectedAudioID = selection.selectedAudioTrackID ?? selection.audioTracks.first?.id
            selectedSubtitleID = selection.selectedSubtitleTrackID.flatMap { selected in
                subtitleTracks.contains(where: { $0.id == selected }) ? selected : nil
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
            ErrorReporter.capture(error)
        }
    }
}

@MainActor
struct DownloadOptionsSections: View {
    @Bindable var model: DownloadOptionsViewModel

    var body: some View {
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
    let onDownload: (TranscodeQualityPreset, MediaDownloadTrackPreference) async -> Void
    @State private var isSubmitting = false

    init(
        itemID: String,
        services: MediaServices,
        defaultQuality: TranscodeQualityPreset,
        onDownload: @escaping (TranscodeQualityPreset, MediaDownloadTrackPreference) async -> Void,
    ) {
        _model = State(initialValue: DownloadOptionsViewModel(
            itemID: itemID,
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
                            await onDownload(model.quality, model.preference)
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || (model.showsTrackSelection && model.selectedAudioID == nil))
                }
            }
            .task(id: model.quality) {
                await model.loadTracksIfNeeded()
            }
        }
    }
}
