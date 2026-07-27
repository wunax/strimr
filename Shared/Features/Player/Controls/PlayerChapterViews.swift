import SwiftUI

extension PlexChapter {
    var displayTitle: String {
        String(localized: "player.chapters.number \(index)")
    }

    var startTimeText: String {
        playerTimestampText(startTime)
    }

    func accessibilityDescription(totalCount: Int, isCurrent: Bool) -> String {
        if isCurrent {
            return String(
                localized: "player.chapters.accessibility.current \(index) \(totalCount) \(startTimeText)",
            )
        }
        return String(
            localized: "player.chapters.accessibility \(index) \(totalCount) \(startTimeText)",
        )
    }
}

struct PlayerChapterArtworkView: View {
    var imageURL: URL?

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlayerSegmentedTimelineRail: View {
    var chapters: [PlexChapter]
    var duration: Double?
    var position: Double
    var bufferedEnd: Double
    var horizontalInset: CGFloat = 14
    var trackHeight: CGFloat = 4
    var preferredGap: CGFloat = 4

    private let minimumGap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let timelineDuration = effectiveDuration
            let rects = segmentRects(
                width: proxy.size.width,
                duration: timelineDuration,
            )
            let playedX = timelineX(
                for: position,
                width: proxy.size.width,
                duration: timelineDuration,
            )
            let bufferedX = timelineX(
                for: bufferedEnd,
                width: proxy.size.width,
                duration: timelineDuration,
            )

            ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.35)

                    Color.white.opacity(0.65)
                        .frame(width: fillWidth(endingAt: bufferedX, in: rect))

                    Color.white
                        .frame(width: fillWidth(endingAt: playedX, in: rect))
                }
                .frame(width: rect.width, height: trackHeight)
                .clipShape(Capsule())
                .position(x: rect.midX, y: proxy.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var effectiveDuration: Double {
        if let duration, duration.isFinite, duration > 0 {
            return duration
        }

        let knownExtent = [position, bufferedEnd]
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 0
        return max(knownExtent, 1)
    }

    private func segmentRects(width: CGFloat, duration: Double) -> [CGRect] {
        let usableWidth = max(width - horizontalInset * 2, 0)
        guard usableWidth > 0 else { return [] }

        let hasKnownDuration = self.duration.map {
            $0.isFinite && $0 > 0
        } ?? false
        let validStarts = hasKnownDuration
            ? chapters
            .filter(\.isValid)
            .map(\.startTime)
            .filter { $0.isFinite && $0 > 0 && $0 < duration }
            .sorted()
            : []

        var distinctStarts: [Double] = []
        for start in validStarts {
            if let previous = distinctStarts.last,
               abs(start - previous) < 0.001
            {
                continue
            }
            distinctStarts.append(start)
        }

        let candidateBoundaries = [horizontalInset]
            + distinctStarts.map { start in
                horizontalInset + usableWidth * CGFloat(start / duration)
            }
            + [horizontalInset + usableWidth]
        let minimumSpan = trackHeight + minimumGap
        var boundaries = [candidateBoundaries[0]]

        for boundary in candidateBoundaries.dropFirst().dropLast() {
            guard let previous = boundaries.last,
                  boundary - previous >= minimumSpan,
                  horizontalInset + usableWidth - boundary >= minimumSpan
            else {
                continue
            }
            boundaries.append(boundary)
        }
        boundaries.append(horizontalInset + usableWidth)

        let spans = zip(boundaries, boundaries.dropFirst()).map { $1 - $0 }
        let smallestSpan = spans.min() ?? usableWidth
        let gap = min(preferredGap, max(minimumGap, smallestSpan - trackHeight))
        let lastSegmentIndex = boundaries.count - 2

        return (0 ... lastSegmentIndex).compactMap { index in
            let leadingGap = index == 0 ? 0 : gap / 2
            let trailingGap = index == lastSegmentIndex ? 0 : gap / 2
            let minX = boundaries[index] + leadingGap
            let maxX = boundaries[index + 1] - trailingGap
            guard maxX > minX else { return nil }
            return CGRect(
                x: minX,
                y: 0,
                width: maxX - minX,
                height: trackHeight,
            )
        }
    }

    private func timelineX(for time: Double, width: CGFloat, duration: Double) -> CGFloat {
        let usableWidth = max(width - horizontalInset * 2, 0)
        let safeTime = time.isFinite ? time : 0
        let progress = CGFloat(min(max(safeTime / duration, 0), 1))
        return horizontalInset + usableWidth * progress
    }

    private func fillWidth(endingAt x: CGFloat, in rect: CGRect) -> CGFloat {
        min(max(x - rect.minX, 0), rect.width)
    }
}

func playerTimestampText(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let totalSeconds = Int(value.rounded())
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
