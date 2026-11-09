import SwiftUI

/// Shown while a channel tunes: the program's artwork under a scrim, instead of a black screen.
struct LiveTVJoinBackdropView: View {
    let channel: LiveTVChannel
    let program: LiveTVProgram?

    var body: some View {
        ZStack {
            Color.black
            if let path = program?.artPath ?? program?.thumbPath {
                ArtworkPathView(path: path, width: 1920, height: 1080)
                    .accessibilityHidden(true)
            }
            Color.overlayScrim
            VStack(spacing: 16) {
                if channel.thumbPath != nil {
                    LiveTVChannelLogo(channel: channel)
                        .frame(width: 180, height: 72)
                }
                if let program {
                    Text(program.title)
                        .font(.heroTitle)
                        .foregroundStyle(.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                Text(channel.displayTitle)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
                ProgressView()
                    .padding(.top, 8)
            }
            .padding(40)
            .videoTextShadow()
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }
}
