import Observation
import SwiftUI

struct SeerrMediaDetailHeaderSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    @Binding var isSummaryExpanded: Bool
    let heroHeight: CGFloat
    let onRequestTap: () -> Void
    let onManageRequestsTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroBackground

            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: heroHeight - 40)

                headerSection
                badgesSection
                ratingsSection
                if !viewModel.isRequestButtonHidden {
                    requestSection
                }

                if viewModel.shouldShowManageRequestsButton {
                    manageRequestsSection
                }

                if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                }

                if let summary = viewModel.media.overview, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.bodyText)
                            .foregroundStyle(.textSecondary)
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

                if let status = viewModel.media.status, !status.isEmpty {
                    metaRow(label: String(localized: "seerr.detail.status"), value: status)
                }

                if let creatorsText = viewModel.creatorsText {
                    metaRow(label: String(localized: "seerr.detail.createdBy"), value: creatorsText)
                }

                if let productionText = viewModel.productionText {
                    metaRow(label: String(localized: "seerr.detail.production"), value: productionText)
                }

                if let countriesText = viewModel.countriesText {
                    metaRow(label: String(localized: "seerr.detail.countries"), value: countriesText)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading {
                    ProgressView("media.detail.updating")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.displayTitle)
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)

            if let status = viewModel.media.mediaInfo?.status {
                SeerrAvailabilityBadgeView(
                    status: status,
                    showsLabel: true,
                    isDownloading: viewModel.isDownloading,
                )
            }
        }
    }

    private var badgesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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

                if let seasons = viewModel.seasonCountText {
                    badge(text: seasons, systemImage: "rectangle.stack")
                }

                if let episodes = viewModel.episodesCountText {
                    badge(text: episodes, systemImage: "tv")
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var ratingsSection: some View {
        SeerrRatingsRow(ratings: viewModel.ratings)
    }

    private var requestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onRequestTap) {
                Label(LocalizedStringKey(viewModel.requestButtonTitleKey), systemImage: requestButtonIcon)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .actionButtonStyle(.primary)
            .disabled(viewModel.isRequestButtonDisabled)

            if let reasonKey = viewModel.requestButtonDisabledReasonKey {
                Text(LocalizedStringKey(reasonKey))
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    private var manageRequestsSection: some View {
        Button(action: onManageRequestsTap) {
            Label(
                String(localized: "seerr.manageRequests.action \(viewModel.pendingManageRequestsCount)"),
                systemImage: "checkmark.seal.fill",
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .actionButtonStyle(.secondary)
    }

    private var requestButtonIcon: String {
        viewModel.pendingRequest == nil ? "paperplane.fill" : "square.and.pencil"
    }

    @ViewBuilder
    private var genresSection: some View {
        if !viewModel.genres.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("media.detail.genres")
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.genres, id: \.self) { genre in
                            badge(text: genre)
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
                            Color.surfaceSubtle
                                .mask(heroMask)
                        case .failure:
                            Color.surfaceSubtle
                                .mask(heroMask)
                        @unknown default:
                            Color.surfaceSubtle
                                .mask(heroMask)
                        }
                    }
                } else {
                    Color.surfaceSubtle
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
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .glassSurface()
    }

    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .eyebrowStyle()
                .foregroundStyle(.textSecondary)
            Text(value)
                .font(.bodyText)
                .foregroundStyle(.textPrimary)
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
}
