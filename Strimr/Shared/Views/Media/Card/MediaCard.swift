import SwiftUI

struct MediaCard: View {
    enum Layout {
        case landscape
        case portrait

        var aspectRatio: CGFloat {
            switch self {
            case .landscape:
                return 16 / 9
            case .portrait:
                return 2 / 3
            }
        }
    }

    let layout: Layout
    let media: MediaItem
    let imageURL: URL?
    let onTap: () -> Void

    private var progress: Double? {
        media.viewProgressPercentage.map { $0 / 100 }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                MediaImageView(url: imageURL, aspectRatio: layout.aspectRatio)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        if let progress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(.brandPrimary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 10)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = subtitle(for: media) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for media: MediaItem) -> String? {
        if media.primaryLabel != media.title {
            return media.primaryLabel
        }
        return media.secondaryLabel
    }
}
