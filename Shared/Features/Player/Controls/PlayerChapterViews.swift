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

struct PlayerChapterTicksView: View {
    var chapters: [PlexChapter]
    var duration: Double?
    var horizontalInset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            if let duration, duration > 0 {
                let usableWidth = max(proxy.size.width - horizontalInset * 2, 0)

                ForEach(
                    chapters.filter { $0.startTime > 0 && $0.startTime < duration },
                    id: \.stableID,
                ) { chapter in
                    let progress = min(max(chapter.startTime / duration, 0), 1)
                    Rectangle()
                        .fill(.black.opacity(0.72))
                        .frame(width: 3, height: 12)
                        .overlay {
                            Rectangle()
                                .fill(.white.opacity(0.9))
                                .frame(width: 1, height: 10)
                        }
                        .position(
                            x: horizontalInset + usableWidth * progress,
                            y: proxy.size.height / 2,
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
