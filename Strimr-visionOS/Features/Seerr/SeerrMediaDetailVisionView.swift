import SwiftUI

struct SeerrMediaDetailVisionView: View {
    @State var viewModel: SeerrMediaDetailViewModel
    let onSelectMedia: (SeerrMedia) -> Void
    @State private var isShowingRequestSheet = false

    init(
        viewModel: SeerrMediaDetailViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroSection

                buttonsRow

                if viewModel.media.mediaType == .tv {
                    seasonsSection
                }

                SeerrCastSection(viewModel: viewModel)

                SeerrRelatedSection(
                    viewModel: viewModel,
                    section: .recommendations,
                    onSelectMedia: onSelectMedia,
                )

                SeerrRelatedSection(
                    viewModel: viewModel,
                    section: .similar,
                    onSelectMedia: onSelectMedia,
                )
            }
            .padding(24)
        }
        .task {
            await viewModel.loadDetails()
        }
        .task {
            await viewModel.loadRelatedContent()
        }
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 24) {
            SeerrMediaArtworkView(
                media: viewModel.media,
                width: 500,
                height: 280,
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.displayTitle)
                    .font(.largeTitle.bold())
                    .lineLimit(2)

                if let year = viewModel.yearText {
                    Text(year)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if let overview = viewModel.media.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }

                if let status = viewModel.media.mediaInfo?.status {
                    SeerrAvailabilityBadgeView(status: status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttonsRow: some View {
        HStack(spacing: 16) {
            if !viewModel.isRequestButtonHidden {
                Button {
                    isShowingRequestSheet = true
                } label: {
                    Label(
                        LocalizedStringKey(viewModel.requestButtonTitleKey),
                        systemImage: "plus.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .disabled(viewModel.isRequestButtonDisabled)
            }

            if viewModel.shouldShowManageRequestsButton {
                NavigationLink {
                    if let manageVM = viewModel.makeManageRequestsViewModel() {
                        SeerrManageRequestsVisionView(viewModel: manageVM)
                    }
                } label: {
                    Label("seerr.manageRequests.title", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $isShowingRequestSheet) {
            if let requestVM = viewModel.makeRequestViewModel() {
                SeerrMediaRequestVisionView(viewModel: requestVM)
            }
        }
    }

    @ViewBuilder
    private var seasonsSection: some View {
        if !viewModel.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.seasons) { season in
                            Button {
                                if let number = season.seasonNumber {
                                    Task { await viewModel.selectSeason(number: number) }
                                }
                            } label: {
                                Text(viewModel.seasonTitle(for: season))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                viewModel.selectedSeason?.id == season.id
                                                    ? Color.brandPrimary.opacity(0.5)
                                                    : Color.secondary.opacity(0.1)
                                            ),
                                    )
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .hoverEffect()
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !viewModel.episodes.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 16)],
                        spacing: 16,
                    ) {
                        ForEach(viewModel.episodes) { episode in
                            SeerrEpisodeCardView(
                                episode: episode,
                                imageURL: viewModel.episodeImageURL(for: episode, width: 300),
                                label: viewModel.episodeLabel(for: episode),
                                airDateText: viewModel.episodeAirDateText(for: episode),
                            )
                        }
                    }
                }
            }
        }
    }
}

struct SeerrMediaRequestVisionView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: SeerrMediaRequestViewModel

    init(viewModel: SeerrMediaRequestViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("seerr.request.description")
                    .foregroundStyle(.secondary)

                if viewModel.isSubmitting {
                    ProgressView("seerr.request.submitting")
                } else if viewModel.didComplete {
                    Label("seerr.request.success", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    Button {
                        Task { await viewModel.submitRequest() }
                    } label: {
                        Text("seerr.request.submit")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(32)
            .navigationTitle("seerr.request.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.close") { dismiss() }
                }
            }
        }
    }
}
