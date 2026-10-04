import Foundation

extension MediaDisplayItem {
    var listSubtitle: String? {
        guard case let .playable(item) = self else { return secondaryLabel }
        switch item.type {
        case .episode:
            let parts = [item.grandparentTitle, item.tertiaryLabel].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .season:
            return item.parentTitle
        default:
            // The year already leads the metadata line.
            let label = item.secondaryLabel
            return label == item.year.map(String.init) ? nil : label
        }
    }

    /// Year, runtime, content rating and rating, skipping missing values; `nil` when none is known.
    var listMetadataLine: String? {
        guard let item = playableItem else { return nil }
        let parts = [
            item.year.map(String.init),
            item.duration.flatMap { $0 >= 60 ? $0.mediaDurationText() : nil },
            item.contentRating.flatMap { $0.isEmpty ? nil : $0 },
            item.rating.map { "★ " + $0.formatted(.number.precision(.fractionLength(1))) },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var usesWideListArtwork: Bool {
        type == .episode || type == .clip
    }
}
