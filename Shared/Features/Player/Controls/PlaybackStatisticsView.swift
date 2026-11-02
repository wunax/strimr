import SwiftUI

/// Refreshes once a second, the rate of the engine's live telemetry, and only while it is on screen.
struct PlaybackStatisticsOverlay: View {
    let controller: PlayerController
    let viewModel: PlayerViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            PlaybackStatisticsPanel(
                statistics: controller.playbackStatistics(context: viewModel.playbackStatisticsContext),
            )
        }
        .allowsHitTesting(false)
    }
}

/// Takes the fewest columns that fit the height it is offered, so it never runs off a short screen.
struct PlaybackStatisticsPanel: View {
    let statistics: PlaybackStatistics

    var body: some View {
        ViewThatFits(in: .vertical) {
            #if os(tvOS)
                // A single column covers most of a TV picture; two keep the lower half clear.
                panel(columns: 2)
                panel(columns: 3)
            #else
                panel(columns: 1)
                panel(columns: 2)
                panel(columns: 3)
            #endif
        }
    }

    private func panel(columns count: Int) -> some View {
        let columns = statistics.columns(count)
        return HStack(alignment: .top, spacing: Metrics.columnGap) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, sections in
                column(sections)
                    .frame(maxWidth: Metrics.columnWidth, alignment: .leading)
            }
        }
        .font(.cardMetadata)
        .lineLimit(2)
        .padding(Metrics.padding)
        .videoOverlayGlass(
            in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous),
        )
        .accessibilityElement(children: .contain)
    }

    private func column(_ sections: [PlaybackStatistics.Section]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.labelGap, verticalSpacing: 3) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                GridRow {
                    Text(section.kind.title)
                        .eyebrowStyle()
                        .foregroundStyle(.textTertiary)
                        .gridCellColumns(2)
                        .padding(.top, index == 0 ? 0 : Metrics.sectionSpacing)
                }

                ForEach(section.rows) { row in
                    GridRow {
                        Text(row.field.title)
                            .foregroundStyle(.textSecondary)
                        Text(row.value)
                            .foregroundStyle(.textPrimary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private enum Metrics {
        #if os(tvOS)
            static let padding: CGFloat = 28
            static let labelGap: CGFloat = 20
            static let columnGap: CGFloat = 40
            static let sectionSpacing: CGFloat = 12
            static let columnWidth: CGFloat = 640
        #else
            static let padding: CGFloat = 14
            static let labelGap: CGFloat = 12
            static let columnGap: CGFloat = 24
            static let sectionSpacing: CGFloat = 8
            static let columnWidth: CGFloat = 400
        #endif
    }
}
