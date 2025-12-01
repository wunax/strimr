import SwiftUI

struct MediaImageView: View {
    let url: URL?
    let aspectRatio: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    VStack {
                        Image(systemName: "film")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No artwork")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    case .failure:
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fill)
            }
        }
    }
}
