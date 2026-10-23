import Observation
import SwiftUI

struct SeerrMediaDetailHeaderSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    let onRequestTap: () -> Void
    let onManageRequestsTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            hero
            details
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                AsyncImage(url: viewModel.heroImageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.black.opacity(0.25)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(Color.black.opacity(0.2))
                .mask(LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom))
            }
            .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 480)

            SeerrDetailHeroTitle(viewModel: viewModel, alignment: .leading)
                .padding(28)
        }
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 480)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            actions

            if let summaryText {
                summaryText
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 900, alignment: .leading)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.isLoading {
                ProgressView("media.detail.updating")
            }
        }
        .padding(.horizontal, 28)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if !viewModel.isRequestButtonHidden {
                    Button(action: onRequestTap) {
                        Label(LocalizedStringKey(viewModel.requestButtonTitleKey), systemImage: requestButtonIcon)
                            .frame(minWidth: 160)
                    }
                    .actionButtonStyle(.primary)
                    .disabled(viewModel.isRequestButtonDisabled)
                }

                if viewModel.shouldShowManageRequestsButton {
                    Button(action: onManageRequestsTap) {
                        Label(
                            String(localized: "seerr.manageRequests.action \(viewModel.pendingManageRequestsCount)"),
                            systemImage: "checkmark.seal.fill",
                        )
                    }
                    .actionButtonStyle(.secondary)
                }
            }

            if !viewModel.isRequestButtonHidden, let reasonKey = viewModel.requestButtonDisabledReasonKey {
                Text(LocalizedStringKey(reasonKey))
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    private var requestButtonIcon: String {
        viewModel.pendingRequest == nil ? "paperplane.fill" : "square.and.pencil"
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
}
