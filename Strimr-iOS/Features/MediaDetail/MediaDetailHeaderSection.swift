import Observation
import SwiftUI

struct MediaDetailHeaderSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    @Binding var isSummaryExpanded: Bool
    let heroHeight: CGFloat
    let onPlay: (String, PlexItemType) -> Void
    let onPlayFromStart: (String, PlexItemType) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroBackground

            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: heroHeight - 40)

                headerSection
                playButtonsRow
                secondaryButtonsRow
                badgesSection

                if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if let summary = viewModel.media.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isSummaryExpanded ? nil : 3)

                        Button(action: { isSummaryExpanded.toggle() }) {
                            Text(isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .tint(.brandSecondary)
                        }
                        .tint(.accentColor)
                    }
                }

                genresSection

                if let studio = viewModel.media.studio {
                    metaRow(label: String(localized: "media.detail.studio"), value: studio)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let watchActionErrorMessage = viewModel.watchActionErrorMessage {
                    Label(watchActionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading {
                    ProgressView("media.detail.updating")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.media.primaryLabel)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let secondary = viewModel.media.secondaryLabel {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = viewModel.media.tertiaryLabel {
                Text(tertiary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badgesSection: some View {
        HStack(spacing: 8) {
            if let year = viewModel.yearText {
                badge(text: year)
            }

            if let runtime = viewModel.runtimeText {
                badge(text: runtime, systemImage: "clock")
            }

            if let rating = viewModel.ratingText {
                badge(text: rating, systemImage: "star.fill")
            }

            if let contentRating = viewModel.media.contentRating {
                badge(text: contentRating)
            }
        }
    }

    private var genresSection: some View {
        Group {
            if !viewModel.media.genres.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("media.detail.genres")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.media.genres, id: \.self) { genre in
                                badge(text: genre)
                            }
                        }
                    }
                }
            }
        }
    }

    private var heroBackground: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                if let heroURL = viewModel.heroImageURL {
                    AsyncImage(url: heroURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: heroHeight, alignment: .center)
                                .clipped()
                                .overlay(Color.black.opacity(0.2))
                                .mask(heroMask)
                        case .empty:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        case .failure:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        @unknown default:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        }
                    }
                } else {
                    Color.gray.opacity(0.12)
                        .frame(width: proxy.size.width, height: heroHeight)
                        .mask(heroMask)
                }
            }
            .frame(height: heroHeight)
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight, maxHeight: heroHeight)
        .ignoresSafeArea(edges: .horizontal)
    }

    private func badge(text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }

    private var secondaryButtonsRow: some View {
        HStack(spacing: 12) {
            watchToggleButton

            if viewModel.shouldShowWatchlistButton {
                watchlistToggleButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var playButtonsRow: some View {
        HStack(spacing: 12) {
            playButton

            if viewModel.shouldShowPlayFromStartButton {
                playFromStartButton
            }
        }
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                PlayProgressIcon(progress: viewModel.primaryActionProgress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryActionTitle)
                        .fontWeight(.semibold)
                    if let detail = viewModel.primaryActionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.brandSecondary)
        .foregroundStyle(.brandSecondaryForeground)
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.brandSecondary)
        .accessibilityLabel(Text("media.detail.playFromStart"))
    }

    private var watchToggleButton: some View {
        VStack(spacing: 2) {
            Button {
                Task {
                    await viewModel.toggleWatchStatus()
                }
            } label: {
                if viewModel.isUpdatingWatchStatus {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else {
                    Image(systemName: viewModel.watchActionIcon)
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)

            Text(viewModel.watchActionTitle)
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 48)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var watchlistToggleButton: some View {
        VStack(spacing: 2) {
            Button {
                Task {
                    await viewModel.toggleWatchlistStatus()
                }
            } label: {
                if viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else {
                    Image(systemName: viewModel.watchlistActionIcon)
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isLoading || viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus)

            Text(viewModel.watchlistActionTitle)
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 48)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func handlePlay() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlay(ratingKey, playbackType)
        }
    }

    private func handlePlayFromStart() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlayFromStart(ratingKey, playbackType)
        }
    }

    private var playbackType: PlexItemType {
        viewModel.onDeckItem?.type ?? viewModel.media.type
    }
}

private struct PlayProgressIcon: View {
    let progress: Double?

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(Color.brandSecondaryForeground.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.brandSecondaryForeground,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: "play.fill")
                .font(.title3.weight(.semibold))
        }
        .frame(width: 30, height: 30)
    }
}
