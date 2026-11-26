import SwiftUI

@MainActor
struct SeerrMediaDetailView: View {
    @State var viewModel: SeerrMediaDetailViewModel
    @State private var explore: ExploreDetailViewModel?
    let onSelectMedia: (SeerrMedia) -> Void
    let onSelectCopy: (MediaItem) -> Void
    @State private var requestSheet: SeerrMediaRequestSheetState?
    @State private var manageRequestsSheet: SeerrManageRequestsSheetState?
    #if os(iOS)
        @State private var isSummaryExpanded = false
        @State private var containerSize: CGSize = .zero
    #endif

    init(
        viewModel: SeerrMediaDetailViewModel,
        explore: ExploreDetailViewModel? = nil,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
        onSelectCopy: @escaping (MediaItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        _explore = State(initialValue: explore)
        self.onSelectMedia = onSelectMedia
        self.onSelectCopy = onSelectCopy
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                #if os(iOS)
                    SeerrMediaDetailHeaderSection(
                        viewModel: bindableViewModel,
                        isSummaryExpanded: $isSummaryExpanded,
                        heroHeight: LayoutMetrics.detailHeroHeight(for: containerSize),
                        onRequestTap: presentRequestSheet,
                        onManageRequestsTap: presentManageRequestsSheet,
                    )
                #else
                    SeerrMediaDetailHeaderSection(
                        viewModel: bindableViewModel,
                        onRequestTap: presentRequestSheet,
                        onManageRequestsTap: presentManageRequestsSheet,
                    )
                #endif

                if let explore {
                    VStack(alignment: .leading, spacing: 16) {
                        ExploreWatchlistButton(viewModel: explore)
                        ExploreLibrarySection(viewModel: explore, onSelectCopy: onSelectCopy)
                    }
                    .padding(.horizontal, LayoutMetrics.detailSectionMargin)
                }

                if bindableViewModel.media.mediaType == .tv {
                    SeerrSeasonEpisodesSection(viewModel: bindableViewModel)
                }

                SeerrCastSection(viewModel: bindableViewModel)

                SeerrCollectionSection(viewModel: bindableViewModel, onSelectMedia: onSelectMedia)

                SeerrRelatedSection(
                    viewModel: bindableViewModel,
                    section: .recommendations,
                    onSelectMedia: onSelectMedia,
                )

                SeerrRelatedSection(
                    viewModel: bindableViewModel,
                    section: .similar,
                    onSelectMedia: onSelectMedia,
                )

                SeerrDetailFactsSection(viewModel: bindableViewModel)
                    .padding(.horizontal, LayoutMetrics.detailSectionMargin)
                    .padding(.bottom, 32)
            }
        }
        #if os(iOS)
        .ignoresSafeArea(edges: .top)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        #else
        .navigationTitle(bindableViewModel.media.displayTitle)
        #endif
        .task {
            await bindableViewModel.loadDetails()
            explore?.adopt(bindableViewModel.media)
            async let exploreLoad: Void? = explore?.load()
            async let ratings: Void = bindableViewModel.loadRatings()
            async let collection: Void = bindableViewModel.loadCollection()
            _ = await (ratings, collection)
            await bindableViewModel.loadRelatedContent()
            _ = await exploreLoad
        }
        .background(gradientBackground(for: bindableViewModel))
        .sheet(item: $requestSheet) { sheet in
            SeerrMediaRequestSheetView(viewModel: sheet.viewModel) {
                Task {
                    await viewModel.loadDetails()
                    await viewModel.loadRelatedContent()
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $manageRequestsSheet) { sheet in
            SeerrManageRequestsSheetView(viewModel: sheet.viewModel) {
                Task {
                    await viewModel.loadDetails()
                    await viewModel.loadRelatedContent()
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func gradientBackground(for viewModel: SeerrMediaDetailViewModel) -> some View {
        MediaBackdropGradient(colors: viewModel.backdropGradient)
            .ignoresSafeArea()
    }

    private func presentRequestSheet() {
        guard let viewModel = viewModel.makeRequestViewModel() else { return }
        requestSheet = SeerrMediaRequestSheetState(viewModel: viewModel)
    }

    private func presentManageRequestsSheet() {
        guard let viewModel = viewModel.makeManageRequestsViewModel() else { return }
        manageRequestsSheet = SeerrManageRequestsSheetState(viewModel: viewModel)
    }

    private var sectionSpacing: CGFloat {
        #if os(iOS)
            16
        #else
            24
        #endif
    }
}

private struct SeerrMediaRequestSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrMediaRequestViewModel
}

private struct SeerrManageRequestsSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrManageRequestsViewModel
}
