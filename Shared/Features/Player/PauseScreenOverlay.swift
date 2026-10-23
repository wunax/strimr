import SwiftUI

@MainActor
struct PauseScreenOverlay: View {
    let media: MediaItem
    let position: Double
    let duration: Double?
    let playbackRate: Float
    let showsEndsAtTime: Bool
    let isLive: Bool

    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            scrim

            details
                .frame(maxWidth: maxDetailsWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .foregroundStyle(.textPrimary)
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
                .eyebrowStyle()
                .foregroundStyle(.textSecondary)

            if media.type == .episode, let seriesTitle = media.grandparentTitle {
                Text(seriesTitle)
                    .font(.sectionTitle)
                    .lineLimit(1)
            }

            Text(media.title)
                .font(.heroTitle)
                .lineLimit(2)

            if let metadataText = media.playerMetadataText {
                Text(metadataText)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }

            if let summary = media.summary, !summary.isEmpty,
               !media.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection)
            {
                Text(summary)
                    .font(.bodyText)
                    .lineLimit(summaryLineLimit)
                    .padding(.top, 4)
            }

            if !isLive {
                TimelineView(.everyMinute) { context in
                    if let timeText = timeText(now: context.date) {
                        Text(timeText)
                            .font(.facts.weight(.medium))
                            .foregroundStyle(.textSecondary)
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
