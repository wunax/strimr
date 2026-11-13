#if os(iOS) || os(macOS)
    import Charts
    import SwiftUI

    struct PlexMetricChart: View {
        let points: [PlexDashboardPoint]
        let unit: String
        let percentage: Bool

        /// Series in the order the repository emits them, so each keeps its color in every language.
        private var series: [String] {
            var seen: Set<String> = []
            return points.map(\.series).filter { seen.insert($0).inserted }
        }

        private var usesKilobits: Bool {
            unit == "Mbps" && (points.map(\.value).max() ?? 0) < 1
        }

        private var displayUnit: String {
            usesKilobits ? "kbps" : unit
        }

        private var scale: Double {
            usesKilobits ? 1000 : 1
        }

        private var maximum: Double {
            percentage ? max(100, points.map(\.value).max() ?? 100) : max(
                0.1,
                (points.map(\.value).max() ?? 0) * 1.1,
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { values }
                    VStack(alignment: .leading, spacing: 6) { values }
                }
                Chart(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value(displayUnit, point.value * scale))
                        .foregroundStyle(by: .value("Series", point.series))
                        .lineStyle(by: .value("Series", point.series))
                        .interpolationMethod(.linear)
                        .accessibilityLabel(point.series)
                        .accessibilityValue(formatted(point.value))
                }
                .chartYScale(domain: 0 ... maximum * scale)
                .chartYAxisLabel(displayUnit)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.minute().second())
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .chartForegroundStyleScale(domain: series, range: [Color.blue, Color.orange])
                .frame(height: 150)
            }
        }

        private var values: some View {
            ForEach(series, id: \.self) { series in
                let value = points.last { $0.series == series }?.value ?? 0
                VStack(alignment: .leading, spacing: 3) {
                    Text(series).font(.caption).foregroundStyle(.secondary)
                    Text(formatted(value))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                }
            }
        }

        private func formatted(_ value: Double) -> String {
            unit == "Mbps" ? PlexDashboardFormatting.bandwidth(value)
                : "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
        }
    }

    struct PlexActivityChart: View {
        let points: [PlexDashboardPoint]

        var body: some View {
            Chart(points) { point in
                BarMark(x: .value("Date", point.date, unit: .day), y: .value("Hours", point.value))
                    .foregroundStyle(by: .value("Media", point.series))
                    .accessibilityLabel(point.series)
                    .accessibilityValue(PlexDashboardFormatting.duration(point.value * 3600))
            }
            .chartForegroundStyleScale(
                domain: PlexDashboardMediaKind.allCases.map(\.title),
                range: [.green, .pink, .blue, .orange],
            )
            .chartYAxisLabel(String(localized: "plex.dashboard.hours"))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 210)
        }
    }

#endif
