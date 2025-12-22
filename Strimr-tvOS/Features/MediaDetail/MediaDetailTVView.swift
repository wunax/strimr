import Observation
import SwiftUI

struct MediaDetailTVView: View {
    @State var viewModel: MediaDetailViewModel
    @State private var focusedMedia: MediaItem?
    private let onPlay: (String) -> Void
    private let onSelectMedia: (MediaItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String) -> Void = { _ in },
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ZStack {
            MediaHeroBackgroundView(media: bindableViewModel.media)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    MediaHeroContentView(media: focusedMedia ?? bindableViewModel.media)
                        .frame(maxWidth: 800, alignment: .leading)

                    playButton

                    if bindableViewModel.media.type == .show {
                        seasonsSection
                    }

                    CastSection(viewModel: bindableViewModel)
                    RelatedHubsSection(viewModel: bindableViewModel, onSelectMedia: onSelectMedia)
                }
                .padding(.top, 64)
                .padding(.leading, 72)
                .padding(.trailing, 32)
                .padding(.bottom, 40)
            }
        }
        .task {
            await bindableViewModel.loadDetails()
        }
        .onAppear {
            if focusedMedia == nil {
                focusedMedia = bindableViewModel.media
            }
        }
        .onChange(of: bindableViewModel.media) { oldValue, newValue in
            if focusedMedia == nil || focusedMedia?.id == oldValue.id {
                focusedMedia = newValue
            }
        }
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryActionTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let detail = viewModel.primaryActionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandSecondary)
        .foregroundStyle(.brandSecondaryForeground)
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            seasonSelector
            episodesRow
        }
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if (viewModel.isLoadingSeasons || viewModel.isLoading) && viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("media.detail.loadingSeasons")
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.seasons) { season in
                        SeasonPillButton(
                            title: season.title,
                            isSelected: season.id == viewModel.selectedSeasonId,
                            onSelect: {
                                Task { await viewModel.selectSeason(id: season.id) }
                            },
                            onFocus: {
                                focusedMedia = season
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes && viewModel.episodes.isEmpty {
            ProgressView("media.detail.loadingEpisodes")
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 28) {
                    ForEach(viewModel.episodes) { episode in
                        EpisodeArtworkCard(
                            episode: episode,
                            imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                            runtime: viewModel.runtimeText(for: episode),
                            progress: viewModel.progressFraction(for: episode),
                            width: 460,
                            onPlay: {
                                onPlay(episode.id)
                            },
                            onFocus: {
                                focusedMedia = episode
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .focusSection()
        }
    }

    private func handlePlay() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlay(ratingKey)
        }
    }
}

private struct SeasonPillButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(isFocused || isSelected ? Color.brandPrimary : Color.primary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.brandPrimary.opacity(0.2) : Color.gray.opacity(0.12))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(isFocused ? Color.brandSecondary : Color.gray.opacity(0.25), lineWidth: isFocused ? 3 : 1)
                }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                onFocus()
            }
        }
    }
}

private struct EpisodeArtworkCard: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let width: CGFloat
    let onPlay: () -> Void
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onPlay) {
            EpisodeArtworkView(
                episode: episode,
                imageURL: imageURL,
                width: width,
                runtime: runtime,
                progress: progress
            )
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.brandSecondary : .clear, lineWidth: 4)
        }
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                onFocus()
            }
        }
    }
}
