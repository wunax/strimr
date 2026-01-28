import SwiftUI

struct SeerrMediaArtworkView: View {
    let media: SeerrMedia
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let imageURL = TMDBImageService.posterURL(path: media.posterPath, width: width)
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
                    placeholder
                @unknown default:
                    placeholder
                }
            }

            if let badgeText, let badgeColor {
                Text(badgeText.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.9), in: Capsule())
                    .padding(8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(
            RoundedRectangle(cornerRadius: 14, style: .continuous),
        )
    }

    private var badgeText: String? {
        switch media.mediaType {
        case .movie:
            String(localized: .init("seerr.media.badge.movie"))
        case .tv:
            String(localized: .init("seerr.media.badge.series"))
        case .person, .none:
            nil
        }
    }

    private var badgeColor: Color? {
        switch media.mediaType {
        case .movie:
            .blue
        case .tv:
            .purple
        case .person, .none:
            nil
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
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
