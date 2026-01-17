import SwiftUI

struct DownloadStatusIcon: View {
    let state: DownloadState
    let progress: Double
    var lineWidth: CGFloat = 2
    var size: CGFloat? = 22 // Default size for EpisodeItemViews, can be overridden or controlled by frame in parent

    var body: some View {
        Group {
            if state == .downloading {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.primary,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: "square.fill")
                        .font(.system(size: (size ?? 22) * 0.3, weight: .bold)) // Scale inner icon relative to size
                }
            } else {
                Image(systemName: downloadIcon)
                    .font(.headline.weight(.semibold))
            }
        }
    }

    private var downloadIcon: String {
        switch state {
        case .notDownloaded: return "arrow.down.circle"
        case .downloading: return "stop.fill"
        case .downloaded: return "checkmark.circle.fill"
        }
    }
}
