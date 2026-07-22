import Observation
import SwiftUI

@MainActor
struct MacShowDownloadSelectionSheet: View {
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
            ToolbarItem(placement: .cancellationAction) {
                Button("common.actions.cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(submitButtonTitle) { submitSelection() }
                    .disabled(effectiveSelectionCount == 0 || isSubmitting)
            }
        }
        .task { await initializeSheet() }
        .onChange(of: selectedSeasonID) { _, seasonID in
            guard let seasonID else { return }
            Task { await viewModel.selectSeason(id: seasonID) }
        }
    }

    @ViewBuilder
    private var seasonSection: some View {
        if viewModel.isLoadingSeasons, viewModel.seasons.isEmpty {
            Section { ProgressView("media.detail.loadingSeasons") }
        } else {
            Section("downloads.sheet.bySeason") {
                Picker("media.detail.season", selection: seasonBinding) {
                    ForEach(viewModel.seasons) { season in
                        Text(season.title).tag(season.id)
                    }
                }
            }
        }
    }

    private var seasonBinding: Binding<String> {
        Binding(
            get: { selectedSeasonID ?? viewModel.selectedSeasonId ?? viewModel.seasons.first?.id ?? "" },
            set: { selectedSeasonID = $0 },
        )
    }

    private var quickActionsSection: some View {
        Section("downloads.sheet.quickActions") {
            HStack {
                Button("downloads.sheet.selectAll") {
                    selectedEpisodeIDs.formUnion(selectableEpisodeIDs)
                }
                Button("downloads.sheet.clearSelection") { selectedEpisodeIDs = [] }
                    .disabled(selectedEpisodeIDs.isEmpty)
                Spacer()
                Text("downloads.sheet.selectedCount \(effectiveSelectionCount)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var episodesSection: some View {
        Section("downloads.sheet.byEpisode") {
            if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
                ProgressView("media.detail.loadingEpisodes")
            } else if viewModel.episodes.isEmpty {
                Text("media.detail.noEpisodes").foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.episodes) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        let downloaded = statusForRatingKey(episode.id) == .completed
        let selected = selectedEpisodeIDs.contains(episode.id) && !downloaded
        return Button {
            if selected { selectedEpisodeIDs.remove(episode.id) } else { selectedEpisodeIDs.insert(episode.id) }
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .brandSecondary : .secondary)
                VStack(alignment: .leading) {
                    Text(episode.index.map { String(localized: "downloads.sheet.episodeNumber \($0)") }
                        ?? String(localized: "downloads.sheet.episodeUnknown"))
                        .fontWeight(.semibold)
                    Text(episode.title).foregroundStyle(.secondary)
                }
                Spacer()
                if downloaded { Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green) }
                else if statusForRatingKey(episode.id)?.isActive == true { ProgressView().controlSize(.small) }
            }
        }
        .buttonStyle(.plain)
        .disabled(downloaded)
    }

    private func initializeSheet() async {
        await viewModel.loadSeasonsIfNeeded()
        guard let seasonID = viewModel.selectedSeasonId ?? viewModel.seasons.first?.id else { return }
        selectedSeasonID = seasonID
        if viewModel.selectedSeasonId != seasonID || viewModel.episodes.isEmpty {
            await viewModel.selectSeason(id: seasonID)
        }
    }

    private func submitSelection() {
        let episodeIDs = selectedEpisodeIDs.filter { statusForRatingKey($0) != .completed }.sorted()
        guard !episodeIDs.isEmpty else { return }
        isSubmitting = true
        Task {
            await onSubmitSelection(episodeIDs)
            isSubmitting = false
            dismiss()
        }
    }

    private var selectableEpisodeIDs: Set<String> {
        Set(viewModel.episodes.map(\.id).filter { statusForRatingKey($0) != .completed })
    }

    private var effectiveSelectionCount: Int {
        selectedEpisodeIDs.count(where: { statusForRatingKey($0) != .completed })
    }

    private var submitButtonTitle: String {
        isSubmitting
            ? String(localized: "downloads.sheet.submitting")
            : String(localized: "downloads.sheet.submit \(effectiveSelectionCount)")
    }
}
