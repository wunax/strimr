import SwiftUI

/// A channel's logo, or its number and name when the server has none.
struct LiveTVChannelLogo: View {
    let channel: LiveTVChannel
    var showsNumber = false

    var body: some View {
        if let thumbPath = channel.thumbPath {
            ArtworkPathView(path: thumbPath, width: 320, height: 180, contentMode: .fit)
                .accessibilityLabel(Text(channel.displayTitle))
        } else {
            VStack(spacing: 2) {
                if let number = channel.number {
                    Text(number)
                        .font(.cardTitle.monospacedDigit())
                }
                Text(channel.callSign ?? channel.title)
                    .font(.cardMetadata)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.textSecondary)
            .minimumScaleFactor(0.7)
        }
    }
}
