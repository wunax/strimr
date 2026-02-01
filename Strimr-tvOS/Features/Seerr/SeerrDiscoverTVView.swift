import SwiftUI

@MainActor
struct SeerrDiscoverTVView: View {
    @Environment(SeerrFocusModel.self) private var focusModel
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
        ZStack {
            Color("Background").ignoresSafeArea()

            if let heroMedia {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        ZStack(alignment: .topLeading) {
                            SeerrHeroBackgroundView(media: focusModel.focusedMedia ?? heroMedia)
                            SeerrHeroContentView(media: focusModel.focusedMedia ?? heroMedia)
                                .frame(
                                    maxWidth: proxy.size.width * 0.60,
                                    maxHeight: .infinity,
                                    alignment: .topLeading,
                                )
                        }

                        discoverContent
                            .frame(height: proxy.size.height * 0.60)
                    }
                }
            } else {
                emptyState
            }
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: heroMedia?.id) { _, _ in
            updateInitialFocus()
        }
        .onAppear {
            updateInitialFocus()
        }
    }

    private var discoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !viewModel.trending.isEmpty {
                    SeerrMediaSection(title: "integrations.seerr.discover.trending") {
                        SeerrMediaCarousel(
                            items: viewModel.trending,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.popularMovies.isEmpty {
                    SeerrMediaSection(title: "integrations.seerr.discover.popularMovies") {
                        SeerrMediaCarousel(
                            items: viewModel.popularMovies,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.popularTV.isEmpty {
                    SeerrMediaSection(title: "integrations.seerr.discover.popularTV") {
                        SeerrMediaCarousel(
                            items: viewModel.popularTV,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("integrations.seerr.discover.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView("integrations.seerr.discover.loading")
            } else if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroMedia: SeerrMedia? {
        if let media = viewModel.trending.first {
            return media
        }
        if let media = viewModel.popularMovies.first {
            return media
        }
        return viewModel.popularTV.first
    }

    private func updateInitialFocus() {
        guard focusModel.focusedMedia == nil, let heroMedia else { return }
        focusModel.focusedMedia = heroMedia
    }
}
