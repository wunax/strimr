import Observation
import SwiftUI

@MainActor
struct ShowDownloadSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: MediaDetailViewModel
    let onSubmitSelection: ([String]) async -> Void
    let statusForRatingKey: (String) -> DownloadStatus?

    @State private var selectedSeasonID: String?
    @State private var selectedEpisodeIDs: Set<String> = []
    @State private var isSubmitting = false

    var body: some View {
        List {
            seasonSection
            quickActionsSection
            episodesSection
        }
        .navigationTitle("downloads.sheet.title")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("common.actions.cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(submitButtonTitle) {
                    submitSelection()
                }
                .disabled(effectiveSelectionCount == 0 || isSubmitting)
            }
        }
        .task {
            await initializeSheet()
        }
        .onChange(of: selectedSeasonID) { _, newSeasonID in
            guard let newSeasonID else { return }
            Task {
                await viewModel.selectSeason(id: newSeasonID)
            }
        }
    }

    @ViewBuilder
    private var seasonSection: some View {
        if viewModel.isLoadingSeasons, viewModel.seasons.isEmpty {
            Section {
                ProgressView("media.detail.loadingSeasons")
            }
        } else if viewModel.seasons.isEmpty {
            Section {
                Text("media.detail.noSeasons")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("downloads.sheet.bySeason") {
                Picker(
                    "media.detail.season",
                    selection: Binding(
                        get: {
                            selectedSeasonID ?? viewModel.selectedSeasonId ?? viewModel.seasons.first?.id ?? ""
                        },
                        set: { newValue in
                            selectedSeasonID = newValue
                        },
                    ),
                ) {
                    ForEach(viewModel.seasons, id: \.id) { season in
                        Text(season.title)
                            .tag(season.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var quickActionsSection: some View {
        Section("downloads.sheet.quickActions") {
            Button("downloads.sheet.selectAll") {
                selectedEpisodeIDs.formUnion(selectableEpisodeIDsInCurrentSeason)
            }
            .disabled(selectableEpisodeIDsInCurrentSeason.isEmpty)

            Button("downloads.sheet.clearSelection") {
                selectedEpisodeIDs = []
            }
            .disabled(selectedEpisodeIDs.isEmpty)

            Text("downloads.sheet.selectedCount \(effectiveSelectionCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var episodesSection: some View {
        Section("downloads.sheet.byEpisode") {
            if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
                ProgressView("media.detail.loadingEpisodes")
            } else if viewModel.episodes.isEmpty {
                Text("media.detail.noEpisodes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.episodes, id: \.id) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        let isDownloaded = isAlreadyDownloaded(episodeID: episode.id)
        let isSelected = selectedEpisodeIDs.contains(episode.id) && !isDownloaded
        return Button {
            toggleEpisodeSelection(episode.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .brandSecondary : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(episodeNumberTitle(for: episode))
                        .font(.body.weight(.semibold))

                    Text(episode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                statusIndicator(for: episode.id)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDownloaded)
        .opacity(isDownloaded ? 0.6 : 1)
    }

    @ViewBuilder
    private func statusIndicator(for ratingKey: String) -> some View {
        switch statusForRatingKey(ratingKey) {
        case .completed:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .queued:
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case nil:
            EmptyView()
        }
    }

    private var submitButtonTitle: String {
        if isSubmitting {
            return String(localized: "downloads.sheet.submitting")
        }
        return String(localized: "downloads.sheet.submit \(effectiveSelectionCount)")
    }

    private func episodeNumberTitle(for episode: MediaItem) -> String {
        guard let index = episode.index else {
            return String(localized: "downloads.sheet.episodeUnknown")
        }
        return String(localized: "downloads.sheet.episodeNumber \(index)")
    }

    private func toggleEpisodeSelection(_ episodeID: String) {
        guard !isAlreadyDownloaded(episodeID: episodeID) else { return }
        if selectedEpisodeIDs.contains(episodeID) {
            selectedEpisodeIDs.remove(episodeID)
        } else {
            selectedEpisodeIDs.insert(episodeID)
        }
    }

    private func initializeSheet() async {
        await viewModel.loadSeasonsIfNeeded()

        guard !viewModel.seasons.isEmpty else { return }
        let initialSeasonID = selectedSeasonID ?? viewModel.selectedSeasonId ?? viewModel.seasons.first?.id
        guard let initialSeasonID else { return }

        selectedSeasonID = initialSeasonID
        if viewModel.selectedSeasonId != initialSeasonID || viewModel.episodes.isEmpty {
            await viewModel.selectSeason(id: initialSeasonID)
        }
    }

    private func submitSelection() {
        let orderedEpisodeIDs = selectedEpisodeIDs
            .filter { !isAlreadyDownloaded(episodeID: $0) }
            .sorted()
        guard !orderedEpisodeIDs.isEmpty else { return }

        isSubmitting = true
        Task {
            await onSubmitSelection(orderedEpisodeIDs)
            isSubmitting = false
            dismiss()
        }
    }

    private var effectiveSelectionCount: Int {
        selectedEpisodeIDs.count(where: { !isAlreadyDownloaded(episodeID: $0) })
    }

    private var selectableEpisodeIDsInCurrentSeason: Set<String> {
        Set(viewModel.episodes.map(\.id).filter { !isAlreadyDownloaded(episodeID: $0) })
    }

    private func isAlreadyDownloaded(episodeID: String) -> Bool {
        statusForRatingKey(episodeID) == .completed
    }
}
