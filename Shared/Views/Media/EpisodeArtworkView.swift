import SwiftUI

struct EpisodeArtworkView: View {
    let episode: MediaItem
    let imageURL: URL?
    let width: CGFloat
    let runtime: String?
    let progress: Double?
    private let aspectRatio: CGFloat = 16 / 9

    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    Color.gray.opacity(0.15)
                case .failure:
                    Color.gray.opacity(0.15)
                @unknown default:
                    Color.gray.opacity(0.15)
                }
            }
            .frame(width: width)
            .aspectRatio(aspectRatio, contentMode: .fit)

            if let runtime {
                Label {
                    Text(runtime)
                        .font(.caption2)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: width)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.05))
        }
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: episode)
        }
    }
}
