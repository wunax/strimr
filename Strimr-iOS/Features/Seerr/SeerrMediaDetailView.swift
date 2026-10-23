import SwiftUI

@MainActor
struct SeerrMediaDetailView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @State var viewModel: SeerrMediaDetailViewModel
    @State private var isSummaryExpanded = false
    @State private var requestSheet: SeerrMediaRequestSheetState?
    @State private var manageRequestsSheet: SeerrManageRequestsSheetState?
    private let heroHeight: CGFloat = 320

    init(viewModel: SeerrMediaDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SeerrMediaDetailHeaderSection(
                    viewModel: bindableViewModel,
                    isSummaryExpanded: $isSummaryExpanded,
                    heroHeight: heroHeight,
                    onRequestTap: presentRequestSheet,
                    onManageRequestsTap: presentManageRequestsSheet,
                )

                if bindableViewModel.media.mediaType == .tv {
                    SeerrSeasonEpisodesSection(viewModel: bindableViewModel)
                }

                SeerrCastSection(viewModel: bindableViewModel)

                SeerrCollectionSection(viewModel: bindableViewModel, onSelectMedia: coordinator.showSeerrMediaDetail)

                SeerrRelatedSection(
                    viewModel: bindableViewModel,
                    section: .recommendations,
                    onSelectMedia: coordinator.showSeerrMediaDetail,
                )

                SeerrRelatedSection(
                    viewModel: bindableViewModel,
                    section: .similar,
                    onSelectMedia: coordinator.showSeerrMediaDetail,
                )

                SeerrDetailFactsSection(viewModel: bindableViewModel)
                    .padding(.horizontal, LayoutMetrics.detailSectionMargin)
                    .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await bindableViewModel.loadDetails()
            async let ratings: Void = bindableViewModel.loadRatings()
            async let collection: Void = bindableViewModel.loadCollection()
            _ = await (ratings, collection)
            await bindableViewModel.loadRelatedContent()
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
}

private struct SeerrMediaRequestSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrMediaRequestViewModel
}

private struct SeerrManageRequestsSheetState: Identifiable {
    let id = UUID()
    let viewModel: SeerrManageRequestsViewModel
}
