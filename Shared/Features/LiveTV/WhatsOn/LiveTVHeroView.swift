import SwiftUI

/// The program in focus, or the first one on air, above the What's On rails.
struct LiveTVHeroView: View {
    let item: LiveTVShelfItem
    let onWatch: () -> Void
    let onDetails: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// On a narrow screen the artwork sits above the text instead of behind it.
    private var stacksArtwork: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stacksArtwork, let path = item.program?.artPath ?? item.program?.thumbPath {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        ArtworkPathView(path: path, width: 960, height: 540)
                    }
                    .clipped()
                    .mediaArtworkStyle()
                    .accessibilityHidden(true)
            }
            if let program = item.program, program.isCurrentlyAiring {
                Text("livetv.player.live")
                    .eyebrowStyle()
                    .foregroundStyle(.liveIndicator)
            }
            Text(item.program?.title ?? item.channel.title)
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
            Text(facts)
                .font(.facts)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
            if let summary = item.program?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            HStack(spacing: 12) {
                if item.program?.isCurrentlyAiring ?? true {
                    Button("livetv.hero.watch", systemImage: "play.fill", action: onWatch)
                        .lineLimit(1)
                        .actionButtonStyle(.primary)
                }
                if item.program != nil {
                    Button("livetv.hero.details", systemImage: "info.circle", action: onDetails)
                        .lineLimit(1)
                        .actionButtonStyle(.secondary)
                }
            }
            .padding(.top, 4)
            #if os(tvOS)
                .focusSection()
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .background(alignment: .trailing) {
            if !stacksArtwork {
                backdrop
            }
        }
        .animation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), value: item.id)
    }

    private var facts: String {
        var parts: [String] = []
        if let program = item.program {
            parts.append(
                program.startDate.formatted(date: .omitted, time: .shortened)
                    + " – " + program.endDate.formatted(date: .omitted, time: .shortened),
            )
            if let episode = program.episodeLabel {
                parts.append(episode)
            }
        }
        parts.append(item.channel.displayTitle)
        return parts.joined(separator: " · ")
    }

    private var backdrop: some View {
        GeometryReader { proxy in
            if let path = item.program?.artPath ?? item.program?.thumbPath {
                ArtworkPathView(path: path, width: 1280, height: 720)
                    .frame(width: proxy.size.width * 0.6, height: proxy.size.height)
                    .clipped()
                    .mask {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .id(path)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}
