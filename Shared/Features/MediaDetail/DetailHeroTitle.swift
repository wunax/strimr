import SwiftUI

/// Logo or title over the bottom of the backdrop, with the facts and ratings under it.
struct DetailHeroTitle: View {
    @Bindable var viewModel: MediaDetailViewModel
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            TitleLogoView(
                media: viewModel.media.mediaItem,
                title: logoTitle,
                logoPath: viewModel.media.mediaItem.preferredLogoPath ?? seriesLogoPath,
                maxSize: LayoutMetrics.heroLogoMaxSize,
                alignment: Alignment(horizontal: alignment, vertical: .bottom),
            )
            .frame(
                maxWidth: .infinity,
                minHeight: LayoutMetrics.heroLogoMaxSize.height / 2,
                alignment: Alignment(horizontal: alignment, vertical: .bottom),
            )

            if let subtitle {
                Text(subtitle)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .lineLimit(2)
            }

            MediaFactsLine(facts: facts, badges: badges)

            OtherEditionsButton(viewModel: viewModel)

            if !viewModel.media.ratings.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.media.ratings.enumerated()), id: \.offset) { _, rating in
                        MediaRatingLabel(rating: rating, iconHeight: 16)
                            .font(.facts)
                    }
                }
                .foregroundStyle(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var isChildItem: Bool {
        [.season, .episode].contains(viewModel.media.type)
    }

    /// Episodes and seasons show their series' logo or name, with their own title under it.
    private var logoTitle: String {
        isChildItem ? viewModel.detailSecondaryLabel ?? viewModel.detailPrimaryLabel : viewModel.detailPrimaryLabel
    }

    private var subtitle: String? {
        isChildItem ? viewModel.detailPrimaryLabel : nil
    }

    private var seriesLogoPath: String? {
        viewModel.parentSeries?.mediaItem.logoPath
    }

    private var facts: MediaFacts {
        MediaFactsFormatter.facts(
            for: viewModel.media.mediaItem,
            seasonCount: viewModel.seasons.isEmpty ? nil : viewModel.seasons.count,
            namesStandardEdition: !viewModel.otherEditions.isEmpty,
        )
    }

    private var badges: [String] {
        guard viewModel.activeVersionID(for: nil) != nil else { return [] }
        return viewModel.selectedVersion?.badgeLabels ?? []
    }
}
