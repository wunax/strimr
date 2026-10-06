import SwiftUI

@MainActor
struct PauseScreenOverlay: View {
    let media: MediaItem
    let position: Double
    let duration: Double?
    let playbackRate: Float
    let showsEndsAtTime: Bool
    let isLive: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            scrim

            details
                .frame(maxWidth: maxDetailsWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private var scrim: some View {
        ZStack {
            Color.black.opacity(0.35)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.85), location: 0),
                    .init(color: .black.opacity(0.5), location: 0.45),
                    .init(color: .clear, location: 0.85),
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing,
            )
        }
        .ignoresSafeArea()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: detailsSpacing) {
            Text("player.pauseScreen.watching")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            if media.type == .episode, let seriesTitle = media.grandparentTitle {
                Text(seriesTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }

            Text(media.title)
                .font(titleFont)
                .lineLimit(2)

            if let metadataText = media.playerMetadataText {
                Text(metadataText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .lineLimit(summaryLineLimit)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 4)
            }

            if !isLive {
                TimelineView(.everyMinute) { context in
                    if let timeText = timeText(now: context.date) {
                        Text(timeText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func timeText(now: Date) -> String? {
        guard let duration, duration.isFinite, duration > 0, position.isFinite else { return nil }

        var items = [String(localized: "media.detail.timeLeft \(max(duration - position, 0).mediaDurationText())")]
        if showsEndsAtTime,
           let endsAtText = playerEndsAtText(
               position: position,
               duration: duration,
               playbackRate: playbackRate,
               now: now,
           )
        {
            items.append(endsAtText)
        }
        return items.joined(separator: " · ")
    }

    private var titleFont: Font {
        #if os(iOS)
            .title2.weight(.bold)
        #else
            .title.weight(.bold)
        #endif
    }

    private var summaryLineLimit: Int {
        #if os(iOS)
            3
        #else
            4
        #endif
    }

    private var detailsSpacing: CGFloat {
        #if os(tvOS)
            12
        #else
            6
        #endif
    }

    private var maxDetailsWidth: CGFloat {
        #if os(tvOS)
            900
        #elseif os(macOS)
            560
        #else
            520
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            80
        #elseif os(macOS)
            40
        #else
            24
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(tvOS)
            70
        #elseif os(macOS)
            40
        #else
            28
        #endif
    }
}
