import SwiftUI

struct MediaImageView: View {
    @State var viewModel: MediaImageViewModel

    var body: some View {
        Group {
            if let url = viewModel.imageURL {
                AsyncImage(url: url) { phase in
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
        .task {
            await viewModel.load()
        }
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("media.placeholder.noArtwork")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
