import Observation
import SwiftUI

enum SeerrRelatedSectionKind {
    case recommendations
    case similar

    var titleKey: LocalizedStringKey {
        switch self {
        case .recommendations:
            "seerr.detail.recommendations"
        case .similar:
            "seerr.detail.similar"
        }
    }
}

struct SeerrRelatedSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    let section: SeerrRelatedSectionKind
    let onSelectMedia: (SeerrMedia) -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(section.titleKey)
                            .font(.headline)
                            .fontWeight(.semibold)

                        if isLoading, items.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    relatedContent
                }
                .padding(.horizontal, 8)
            }
            #if os(iOS)
            .padding(.horizontal, 8)
            #endif
        }
        .textCase(nil)
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
                .font(.subheadline)
        } else if items.isEmpty {
            Text(isLoading ? "media.detail.loadingRelated" : "media.detail.noRelated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            SeerrMediaCarousel(
                items: items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
            )
        }
    }
}
