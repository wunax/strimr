import SwiftUI

struct SeerrRatingsRow: View {
    let ratings: SeerrMediaRatings?

    var body: some View {
        let rt = ratings?.rt
        let imdb = ratings?.imdb
        if rt?.criticsScore != nil || rt?.audienceScore != nil || imdb?.criticsScore != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let rt, let score = rt.criticsScore {
                        ratingBadge(
                            title: String(localized: "seerr.ratings.criticsScore"),
                            value: "\(score)%",
                            systemImage: rt.isCriticsFresh ? "checkmark.seal.fill" : "xmark.seal.fill",
                            tint: rt.isCriticsFresh ? .orange : .secondary,
                            url: rt.url,
                        )
                    }

                    if let rt, let score = rt.audienceScore {
                        ratingBadge(
                            title: String(localized: "seerr.ratings.audienceScore"),
                            value: "\(score)%",
                            systemImage: rt.isAudienceUpright ? "hand.thumbsup.fill" : "hand.thumbsdown.fill",
                            tint: rt.isAudienceUpright ? .orange : .secondary,
                            url: rt.url,
                        )
                    }

                    if let imdb, let score = imdb.criticsScore {
                        ratingBadge(
                            title: "IMDb",
                            value: String(format: "%.1f", locale: .current, score),
                            systemImage: "star.fill",
                            tint: .yellow,
                            url: imdb.url,
                        )
                    }
                }
                #if os(tvOS)
                .padding(.vertical, 4)
                #endif
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func ratingBadge(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        url: String?,
    ) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .glassSurface()

        #if os(tvOS)
            content
        #else
            if let url, let destination = URL(string: url) {
                Link(destination: destination) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        #endif
    }
}
