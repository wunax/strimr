import SwiftUI

/// The whole summary of a title, opened from the cut-off one in the hero.
struct DetailSummaryView: View {
    let media: MediaItem
    let logoPath: String?

    @Environment(\.dismiss) private var dismiss
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var scrollOffset: CGFloat = 0
    @State private var maxScrollOffset: CGFloat = 0

    private let scrollStep: CGFloat = 240

    var body: some View {
        ZStack {
            MediaHeroBackgroundView(media: media)
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 32) {
                header
                // Short summaries sit centered with the header; only long ones get a scrolling area.
                ViewThatFits(in: .vertical) {
                    summaryText
                    scrollingSummary
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.vertical, 80)
        }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleLogoView(media: media, logoPath: logoPath, maxSize: LayoutMetrics.heroLogoMaxSize)
            if let secondary = media.secondaryLabel, media.type != .movie, media.type != .series {
                Text(secondary)
                    .font(.facts.weight(.semibold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
            }
            MediaFactsLine(facts: MediaFactsFormatter.facts(for: media))
        }
    }

    private var summaryText: some View {
        Text(media.summary ?? "")
            .font(.bodyText)
            .foregroundStyle(.textPrimary.opacity(0.85))
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Plain text has nothing to move focus to, so the remote scrolls it directly.
    private var scrollingSummary: some View {
        ScrollView {
            summaryText
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentSize.height - geometry.containerSize.height)
        } action: { _, maxOffset in
            maxScrollOffset = maxOffset
        }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: scroll)
    }

    private func scroll(_ direction: MoveCommandDirection) {
        switch direction {
        case .down:
            scrollOffset = min(scrollOffset + scrollStep, maxScrollOffset)
        case .up:
            scrollOffset = max(scrollOffset - scrollStep, 0)
        default:
            return
        }
        withAnimation(Motion.crossfade) {
            scrollPosition.scrollTo(y: scrollOffset)
        }
    }
}
