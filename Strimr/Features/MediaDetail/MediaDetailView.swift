import SwiftUI

struct MediaDetailView: View {
    @State var viewModel: MediaDetailViewModel
    @State private var isSummaryExpanded = false
    private let heroHeight: CGFloat = 320

    init(viewModel: MediaDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                heroBackground

                VStack(alignment: .leading, spacing: 16) {
                    Spacer().frame(height: heroHeight - 40)

                    headerSection
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
                                Text(isSummaryExpanded ? "Show less" : "Read more")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .tint(.accentColor)
                        }
                    }

                    genresSection

                    if let studio = viewModel.media.studio {
                        metaRow(label: "Studio", value: studio)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    if viewModel.isLoading {
                        ProgressView("Updating details")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails()
        }
        .background(gradientBackground)
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
                    Text("Genres")
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

    private var gradientBackground: some View {
        let colors = viewModel.backdropGradient
        return Group {
            if colors.count >= 2 {
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                Color("Background")
                    .ignoresSafeArea()
            }
        }
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    let api = PlexAPIManager()
    let sample = MediaItem(
        id: "1",
        summary: "A high-stakes story about streaming.",
        title: "Strimr Origins",
        type: .movie,
        genres: ["Drama", "Tech"],
        year: 2024,
        duration: 7200,
        rating: 8.4,
        contentRating: "PG-13",
        studio: "Strimr Studios",
        tagline: "Stream smarter.",
        thumbPath: nil,
        artPath: nil,
        ultraBlurColors: nil,
        viewOffset: nil,
        childCount: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        grandparentThumbPath: nil,
        grandparentArtPath: nil,
        parentThumbPath: nil
    )

    return MediaDetailView(
        viewModel: MediaDetailViewModel(media: sample, plexApiManager: api)
    )
    .environment(api)
}
