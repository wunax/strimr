import Observation
import SwiftUI

enum SeerrRelatedSectionKind {
    case recommendations
    case similar

    var title: String {
        switch self {
        case .recommendations:
            String(localized: "seerr.detail.recommendations")
        case .similar:
            String(localized: "seerr.detail.similar")
        }
    }
}

struct SeerrRelatedSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    let section: SeerrRelatedSectionKind
    let onSelectMedia: (SeerrMedia) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            MediaHubSection(title: section.title) {
                relatedContent
            }
        }
        .padding(.horizontal, LayoutMetrics.detailSectionMargin)
        .environment(\.railPageMargin, LayoutMetrics.detailSectionMargin)
        .padding(.bottom, 32)
    }

    private var items: [SeerrMedia] {
        switch section {
        case .recommendations:
            viewModel.recommendations
        case .similar:
            viewModel.similar
        }
    }

    private var isLoading: Bool {
        switch section {
        case .recommendations:
            viewModel.isLoadingRecommendations
        case .similar:
            viewModel.isLoadingSimilar
        }
    }

    private var errorMessage: String? {
        switch section {
        case .recommendations:
            viewModel.recommendationsErrorMessage
        case .similar:
            viewModel.similarErrorMessage
        }
    }

    @ViewBuilder
    private var relatedContent: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.facts)
        } else if items.isEmpty, isLoading {
            CarouselSkeleton(layout: .portrait)
        } else if items.isEmpty {
            Text("media.detail.noRelated")
                .font(.facts)
                .foregroundStyle(.textSecondary)
        } else {
            SeerrMediaCarousel(
                items: items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
            )
        }
    }
}
