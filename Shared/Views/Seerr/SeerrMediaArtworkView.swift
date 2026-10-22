import SwiftUI

struct SeerrMediaArtworkView: View {
    let media: SeerrMedia
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let imageURL = TMDBImageService.posterURL(path: media.posterPath, width: width)
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                Color.surfaceSubtle
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: width, height: height)
        .mediaArtworkStyle()
        .overlay(alignment: .topTrailing) {
            if let status = media.mediaInfo?.status {
                SeerrAvailabilityBadgeView(status: status, isDownloading: media.mediaInfo?.isDownloading ?? false)
                    .padding(8)
            }
        }
    }

    private var placeholder: some View {
        MediaArtworkPlaceholder(mediaKind: placeholderMediaKind)
    }

    private var placeholderMediaKind: MediaKind? {
        switch media.mediaType {
        case .movie:
            .movie
        case .tv:
            .series
        case .person, nil:
            nil
        }
    }
}
