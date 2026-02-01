import SwiftUI

struct SeerrSearchCard: View {
    let media: SeerrMedia
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                SeerrMediaArtworkView(
                    media: media,
                    width: artworkSize.width,
                    height: artworkSize.height,
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let overview = media.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.08)),
            )
        }
        .buttonStyle(.plain)
    }

    private var artworkSize: CGSize {
        #if os(tvOS)
            CGSize(width: 140, height: 210)
        #else
            CGSize(width: 90, height: 135)
        #endif
    }

    private var title: String {
        switch media.mediaType {
        case .movie:
            media.title ?? media.name ?? ""
        case .tv, .person:
            media.name ?? media.title ?? ""
        case .none:
            media.title ?? media.name ?? ""
        }
    }

    private var subtitle: String? {
        switch media.mediaType {
        case .movie:
            year(from: media.releaseDate)
        case .tv:
            year(from: media.firstAirDate)
        case .person, .none:
            nil
        }
    }

    private func year(from dateString: String?) -> String? {
        guard let dateString, dateString.count >= 4 else {
            return nil
        }

        return String(dateString.prefix(4))
    }
}
