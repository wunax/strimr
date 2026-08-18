import SwiftUI

struct MediaRatingLabel: View {
    let rating: MediaRating
    var iconHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            ratingIcon

            Text(verbatim: rating.formattedValue)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.accessibilityLabel))
    }

    @ViewBuilder
    private var ratingIcon: some View {
        switch rating.source.icon {
        case let .asset(name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(height: iconHeight)
        case let .system(name):
            Image(systemName: name)
                .foregroundStyle(.yellow)
                .font(.system(size: iconHeight))
        }
    }
}
