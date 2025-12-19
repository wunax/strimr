import SwiftUI

struct MediaHeroView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let media: MediaItem

    @State private var imageURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroImage

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.65)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            heroContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task(id: media.id) {
            await loadImage()
        }
    }

    private var heroImage: some View {
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

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(media.primaryLabel)
                .font(.title2.bold())
                .lineLimit(2)

            if let secondary = media.secondaryLabel {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = media.tertiaryLabel {
                Text(tertiary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let summary = media.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(24)
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

    private func loadImage() async {
        let path = media.grandparentArtPath
            ?? media.artPath
            ?? media.grandparentThumbPath
            ?? media.parentThumbPath
            ?? media.thumbPath
        guard let path else {
            imageURL = nil
            return
        }

        do {
            let imageRepository = try ImageRepository(context: plexApiContext)
            imageURL = imageRepository.transcodeImageURL(
                path: path,
                width: 1280,
                height: 720,
                minSize: 1,
                upscale: 1
            )
        } catch {
            imageURL = nil
        }
    }
}

#Preview {
    let sample = MediaItem(
        id: "sample",
        summary: nil,
        title: "Title",
        type: .show,
        parentRatingKey: nil,
        grandparentRatingKey: nil,
        genres: ["Sci-Fi"],
        year: 2024,
        duration: nil,
        rating: nil,
        contentRating: nil,
        studio: nil,
        tagline: nil,
        thumbPath: nil,
        artPath: nil,
        ultraBlurColors: nil,
        viewOffset: nil,
        viewCount: nil,
        childCount: 2,
        leafCount: nil,
        viewedLeafCount: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        grandparentThumbPath: nil,
        grandparentArtPath: nil,
        parentThumbPath: nil
    )

    return MediaHeroView(media: sample)
        .environment(PlexAPIContext())
        .frame(width: 900, height: 420)
        .padding()
        .background(Color("Background"))
}
