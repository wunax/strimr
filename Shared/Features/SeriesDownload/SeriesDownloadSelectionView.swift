import SwiftUI

struct SeriesDownloadSelectionView: View {
    @Environment(MainCoordinator.self) private var coordinator
    @Environment(SettingsManager.self) private var settingsManager
    @State private var viewModel: SeriesDownloadViewModel
    
    init(series: MediaItem, context: PlexAPIContext) {
        _viewModel = State(initialValue: SeriesDownloadViewModel(series: series, context: context))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                List {
                    Section {
                        Text(viewModel.series.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                    }
                    
                    ForEach(viewModel.seasons, id: \.id) { season in
                        Section {
                             seasonHeader(season)
                            
                            if viewModel.expandedSeasonIds.contains(season.id) {
                                if let episodes = viewModel.episodesBySeason[season.id] {
                                    ForEach(episodes, id: \.id) { episode in
                                        episodeRow(episode)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            
            downloadButton
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("media.actions.downloads")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadData()
        }
    }
    
    private func seasonHeader(_ season: MediaItem) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleSeason(season.id)
            } label: {
                Image(systemName: seasonSelectionIcon(season.id))
                    .font(.title3)
                    .foregroundStyle(viewModel.isSeasonSelected(season.id) ? .brandSecondary : .secondary)
            }
            .buttonStyle(.plain)
            
            thumbnail(for: season, size: CGSize(width: 40, height: 60))
            
            Text(season.title)
                .font(.headline)
            
            Spacer()
            
            Button {
                withAnimation {
                    viewModel.toggleExpandSeason(season.id)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .rotationEffect(.degrees(viewModel.expandedSeasonIds.contains(season.id) ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    private func episodeRow(_ episode: MediaItem) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleEpisode(episode.id)
            } label: {
                Image(systemName: viewModel.selectedEpisodeIds.contains(episode.id) ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(viewModel.selectedEpisodeIds.contains(episode.id) ? .brandSecondary : .secondary)
            }
            .buttonStyle(.plain)
            
            thumbnail(for: episode, size: CGSize(width: 70, height: 40))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let index = episode.index {
                    Text("media.detail.episodeNumber \(index)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.leading, 36)
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func thumbnail(for item: MediaItem, size: CGSize) -> some View {
        let url = viewModel.imageURL(for: item, width: Int(size.width * 2), height: Int(size.height * 2))
        
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                Color.white.opacity(0.1)
                    .overlay { ProgressView().controlSize(.small) }
            case .failure:
                Color.white.opacity(0.1)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                Color.white.opacity(0.1)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private var downloadButton: some View {
        VStack {
            Button {
                viewModel.startDownloads()
                if settingsManager.settings.download.showDownloadsAfterShowDownload {
                    coordinator.replaceSelectionWithDownloads()
                } else {
                    coordinator.goBack()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("media.actions.download")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.brandPrimary)
            .disabled(!viewModel.canDownload)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
    }
    
    private func seasonSelectionIcon(_ seasonId: String) -> String {
        if viewModel.isSeasonSelected(seasonId) {
            return "checkmark.circle.fill"
        } else if viewModel.isSeasonIndeterminate(seasonId) {
            return "minus.circle.fill"
        } else {
            return "circle"
        }
    }
}
