import SwiftUI

/// "● LIVE" at the live edge, how far behind otherwise.
struct LiveTVLiveBadge: View {
    let behindLiveSeconds: Double
    let isAtLiveEdge: Bool

    static func isLive(behindLiveSeconds: Double, isAtLiveEdge: Bool) -> Bool {
        isAtLiveEdge || behindLiveSeconds < 2
    }

    var body: some View {
        Group {
            if Self.isLive(behindLiveSeconds: behindLiveSeconds, isAtLiveEdge: isAtLiveEdge) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.liveIndicator)
                        .frame(width: 8, height: 8)
                    Text("livetv.player.live")
                        .textCase(.uppercase)
                }
            } else {
                Text("livetv.player.behindShort \(max(1, Int((behindLiveSeconds / 60).rounded())))")
                    .monospacedDigit()
            }
        }
        .playerBadgeStyle()
    }
}

/// The live row of the player controls: live badge, channel actions and the way back to live.
struct LiveTVPlayerStatusRow: View {
    let behindLiveSeconds: Double
    let isAtLiveEdge: Bool
    let lastChannel: LiveTVChannel?
    let onGoLive: () -> Void
    let onShowChannels: () -> Void
    let onLastChannel: () -> Void

    private var isLive: Bool {
        LiveTVLiveBadge.isLive(behindLiveSeconds: behindLiveSeconds, isAtLiveEdge: isAtLiveEdge)
    }

    var body: some View {
        HStack(spacing: 12) {
            LiveTVLiveBadge(behindLiveSeconds: behindLiveSeconds, isAtLiveEdge: isAtLiveEdge)
            Spacer(minLength: 0)
            if !isLive {
                Button("livetv.player.goLive", systemImage: "dot.radiowaves.left.and.right", action: onGoLive)
                    .actionButtonStyle(.primary)
            }
            #if !os(tvOS)
                if lastChannel != nil {
                    Button("livetv.player.lastChannel", systemImage: "arrow.uturn.backward", action: onLastChannel)
                        .actionButtonStyle(.secondary)
                }
                Button("livetv.player.channels", systemImage: "list.bullet.rectangle", action: onShowChannels)
                    .actionButtonStyle(.secondary)
            #endif
        }
        .animation(Motion.controls, value: isLive)
    }
}
