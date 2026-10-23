import SwiftUI

/// Title over the bottom of the backdrop with the facts, ratings and availability under it, like `DetailHeroTitle`.
/// Seerr has no title logos, so the name always shows.
struct SeerrDetailHeroTitle: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            Text(viewModel.media.displayTitle)
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(
                    maxWidth: .infinity,
                    minHeight: LayoutMetrics.heroLogoMaxSize.height / 2,
                    alignment: Alignment(horizontal: alignment, vertical: .bottom),
                )
                .accessibilityAddTraits(.isHeader)

            MediaFactsLine(facts: MediaFactsFormatter.facts(for: viewModel.media))

            if !ratings.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(ratings.enumerated()), id: \.offset) { _, rating in
                        MediaRatingLabel(rating: rating, iconHeight: 16)
                            .font(.facts)
                    }
                }
                .foregroundStyle(.textSecondary)
            }

            if let status = viewModel.media.mediaInfo?.status {
                SeerrAvailabilityBadgeView(status: status, showsLabel: true, isDownloading: viewModel.isDownloading)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    private var ratings: [MediaRating] {
        MediaRating.ratings(from: viewModel.ratings, voteAverage: viewModel.media.voteAverage)
    }
}

/// Key and value rows closing a Seerr detail page, in the same block as library items.
struct SeerrDetailFactsSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel

    var body: some View {
        DetailFactsList(rows: rows)
    }

    private var rows: [DetailFactRow] {
        var rows: [DetailFactRow] = []
        if !viewModel.genres.isEmpty {
            rows.append(DetailFactRow(
                label: String(localized: "media.detail.genres"),
                value: viewModel.genres.joined(separator: ", "),
            ))
        }
        if let status = viewModel.media.status, !status.isEmpty {
            rows.append(DetailFactRow(label: String(localized: "seerr.detail.status"), value: status))
        }
        if let creators = viewModel.creatorsText {
            rows.append(DetailFactRow(label: String(localized: "seerr.detail.createdBy"), value: creators))
        }
        if let production = viewModel.productionText {
            rows.append(DetailFactRow(label: String(localized: "seerr.detail.production"), value: production))
        }
        if let countries = viewModel.countriesText {
            rows.append(DetailFactRow(label: String(localized: "seerr.detail.countries"), value: countries))
        }
        return rows
    }
}
