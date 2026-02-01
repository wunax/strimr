import SwiftUI

struct HeroImageView: View {
    let imageURL: URL?

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
                        EmptyView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.35)

            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("media.placeholder.noArtwork")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HeroMaskView: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.25),
                .init(color: .clear, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.25),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .trailing,
                endPoint: .leading,
            ),
        )
    }
}
