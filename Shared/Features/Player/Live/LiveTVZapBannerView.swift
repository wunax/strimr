import SwiftUI

/// Briefly shown at the bottom after a channel change: the channel, what is on and what comes next.
struct LiveTVZapBannerView: View {
    let channel: LiveTVChannel
    let current: LiveTVProgram?
    let next: LiveTVProgram?

    var body: some View {
        HStack(spacing: 16) {
            LiveTVChannelLogo(channel: channel)
                .frame(width: logoSize.width, height: logoSize.height)
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.displayTitle)
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                Text(current?.title ?? channel.title)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                if let current {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        CardProgressBar(progress: current.progress(at: context.date))
                    }
                    .frame(maxWidth: 320)
                }
                if let next {
                    Text(
                        "livetv.guide.next \(next.startDate.formatted(date: .omitted, time: .shortened)) \(next.title)",
                    )
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .videoOverlayGlass(in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var logoSize: CGSize {
        #if os(tvOS)
            CGSize(width: 120, height: 68)
        #else
            CGSize(width: 72, height: 44)
        #endif
    }
}
