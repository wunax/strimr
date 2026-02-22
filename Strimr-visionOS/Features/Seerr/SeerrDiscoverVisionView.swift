import SwiftUI

@MainActor
struct SeerrDiscoverVisionView: View {
    @State var viewModel: SeerrDiscoverViewModel
    let onSelectMedia: (SeerrMedia) -> Void

    init(
        viewModel: SeerrDiscoverViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let featured = viewModel.trending.first {
                    heroSection(media: featured)
                }

                if !viewModel.trending.isEmpty {
                    SeerrMediaSection(title: "seerr.discover.trending") {
                        SeerrMediaCarousel(
                            items: viewModel.trending,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.popularMovies.isEmpty {
                    SeerrMediaSection(title: "seerr.discover.popularMovies") {
                        SeerrMediaCarousel(
                            items: viewModel.popularMovies,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.popularTV.isEmpty {
                    SeerrMediaSection(title: "seerr.discover.popularTV") {
                        SeerrMediaCarousel(
                            items: viewModel.popularTV,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.upcomingMovies.isEmpty {
                    SeerrMediaSection(title: "seerr.discover.upcomingMovies") {
                        SeerrMediaCarousel(
                            items: viewModel.upcomingMovies,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.upcomingTV.isEmpty {
                    SeerrMediaSection(title: "seerr.discover.upcomingTV") {
                        SeerrMediaCarousel(
                            items: viewModel.upcomingTV,
                            showsLabels: false,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .task {
            await viewModel.load()
        }
    }

    private func heroSection(media: SeerrMedia) -> some View {
        HStack(alignment: .top, spacing: 24) {
            SeerrMediaArtworkView(
                media: media,
                width: 500,
                height: 280,
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(media.title ?? media.name ?? "")
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                if let overview = media.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Button {
                    onSelectMedia(media)
                } label: {
                    Label("seerr.discover.viewDetails", systemImage: "info.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 16)
    }
}
