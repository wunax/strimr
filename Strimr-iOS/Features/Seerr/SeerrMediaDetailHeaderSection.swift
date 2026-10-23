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
                // The title block straddles the bottom of the backdrop.
                Spacer().frame(height: heroHeight - LayoutMetrics.heroLogoMaxSize.height - 24)

                SeerrDetailHeroTitle(viewModel: viewModel)
                actions
                synopsis

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

    @ViewBuilder
    private var actions: some View {
        if !viewModel.isRequestButtonHidden {
            Button(action: onRequestTap) {
                Label(LocalizedStringKey(viewModel.requestButtonTitleKey), systemImage: requestButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.primary)
            .disabled(viewModel.isRequestButtonDisabled)

            if let reasonKey = viewModel.requestButtonDisabledReasonKey {
                Text(LocalizedStringKey(reasonKey))
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }
        }

        if viewModel.shouldShowManageRequestsButton {
            Button(action: onManageRequestsTap) {
                Label(
                    String(localized: "seerr.manageRequests.action \(viewModel.pendingManageRequestsCount)"),
                    systemImage: "checkmark.seal.fill",
                )
                .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.secondary)
        }
    }

    private var requestButtonIcon: String {
        viewModel.pendingRequest == nil ? "paperplane.fill" : "square.and.pencil"
    }

    @ViewBuilder
    private var synopsis: some View {
        if let summaryText {
            VStack(alignment: .leading, spacing: 8) {
                summaryText
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isSummaryExpanded ? nil : 3)

                Button(action: { isSummaryExpanded.toggle() }) {
                    Text(isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore")
                        .font(.facts)
                        .fontWeight(.semibold)
                        .foregroundStyle(.textPrimary)
                }
            }
        }
    }

    /// The tagline leads the synopsis in semibold instead of taking a line of its own.
    private var summaryText: Text? {
        let tagline = viewModel.media.tagline.flatMap { $0.isEmpty ? nil : $0 }
        let summary = viewModel.media.overview.flatMap { $0.isEmpty ? nil : $0 }
        switch (tagline, summary) {
        case let (tagline?, summary?):
            return Text(verbatim: tagline + " ").fontWeight(.semibold).foregroundStyle(.textPrimary)
                + Text(verbatim: summary)
        case let (tagline?, nil):
            return Text(verbatim: tagline).fontWeight(.semibold).foregroundStyle(.textPrimary)
        case let (nil, summary?):
            return Text(verbatim: summary)
        case (nil, nil):
            return nil
        }
    }

    private var heroBackground: some View {
        GeometryReader { proxy in
            AsyncImage(url: viewModel.heroImageURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: heroHeight, alignment: .center)
                        .clipped()
                        .overlay(Color.black.opacity(0.2))
                } else {
                    Color.surfaceSubtle
                }
            }
            .mask(heroMask)
        }
        .frame(height: heroHeight)
        .heroParallax(height: heroHeight)
        .frame(maxWidth: .infinity, minHeight: heroHeight, maxHeight: heroHeight)
        .ignoresSafeArea(edges: .horizontal)
    }

    private var heroMask: some View {
        LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom)
    }
}
