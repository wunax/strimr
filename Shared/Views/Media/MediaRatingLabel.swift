import SwiftUI

struct MediaRatingLabel: View {
    let rating: MediaRating
    var iconHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            Image(rating.source.assetName)
                .resizable()
                .scaledToFit()
                .frame(height: iconHeight)

            Text(verbatim: rating.formattedValue)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rating.accessibilityLabel))
    }
}
