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

struct PlaybackStatisticsPanel: View {
    let statistics: PlaybackStatistics

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.columnSpacing, verticalSpacing: 3) {
            ForEach(Array(statistics.sections.enumerated()), id: \.element.id) { index, section in
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
        .font(.cardMetadata)
        .lineLimit(2)
        .padding(Metrics.padding)
        .frame(maxWidth: Metrics.maxWidth, alignment: .leading)
        .videoOverlayGlass(
            in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous),
        )
        .accessibilityElement(children: .contain)
    }

    private enum Metrics {
        #if os(tvOS)
            static let padding: CGFloat = 28
            static let columnSpacing: CGFloat = 20
            static let sectionSpacing: CGFloat = 12
            static let maxWidth: CGFloat = 760
        #else
            static let padding: CGFloat = 14
            static let columnSpacing: CGFloat = 12
            static let sectionSpacing: CGFloat = 8
            static let maxWidth: CGFloat = 420
        #endif
    }
}
