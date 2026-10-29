import Foundation

extension MediaDisplayItem {
    var listSubtitle: String? {
        guard case let .playable(item) = self else { return secondaryLabel }
        switch item.type {
        case .episode:
            return Self.joined(item.grandparentTitle, item.tertiaryLabel, item.editionTitle)
        case .season:
            return Self.joined(item.parentTitle, item.editionTitle)
        default:
            // The year already leads the metadata line.
            let label = item.type == .movie ? item.editionTitle : item.secondaryLabel
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

    /// In-progress cards show the time left in place of the year. Editions share the title's artwork and name, so the
    /// caption keeps naming the edition.
    func cardSecondaryLabel(remainingTime: String?) -> String? {
        guard case let .playable(item) = self, item.type != .episode else { return secondaryLabel }
        if let remainingTime {
            return Self.joined(remainingTime, item.editionTitle)
        }
        return item.type == .season ? Self.joined(secondaryLabel, item.editionTitle) : secondaryLabel
    }

    /// Episodes keep their title on the second line, so the edition and the time left follow the episode number.
    func cardTertiaryLabel(remainingTime: String?) -> String? {
        guard case let .playable(item) = self, item.type == .episode else { return tertiaryLabel }
        return Self.joined(tertiaryLabel, item.editionTitle, remainingTime)
    }

    private static func joined(_ parts: String?...) -> String? {
        let parts = parts.compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var usesWideListArtwork: Bool {
        type == .episode || type == .clip
    }
}
