import Foundation

/// Why a title is put forward in the home hero. The order is the priority when a title has several reasons.
enum FeaturedReason: Int, CaseIterable, Codable, Hashable, Comparable {
    /// A collection the server's owner promoted to the home.
    case curated
    case recentlyAdded
    /// A series the user started that came back with new episodes.
    case newSeason
    case trending
    /// Unwatched, well rated and added a while ago.
    case rediscover

    static func < (lhs: FeaturedReason, rhs: FeaturedReason) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct FeaturedCandidate: Hashable, Codable, Identifiable {
    let item: MediaItem
    let reason: FeaturedReason
    /// When the item, or the newest content of a series, was added.
    let addedAt: Date?
    /// Number of the new season; `nil` when only a few episodes were added.
    var newSeasonNumber: Int?
    /// Name of the promoted collection, for `curated`.
    var collectionTitle: String?

    init(
        item: MediaItem,
        reason: FeaturedReason,
        addedAt: Date? = nil,
        newSeasonNumber: Int? = nil,
        collectionTitle: String? = nil,
    ) {
        self.item = item
        self.reason = reason
        self.addedAt = addedAt
        self.newSeasonNumber = newSeasonNumber
        self.collectionTitle = collectionTitle
    }

    var id: MediaIdentity {
        item.identity
    }

    var server: ServerIdentity {
        item.identity.server
    }

    func with(reason: FeaturedReason, from source: FeaturedCandidate) -> FeaturedCandidate {
        FeaturedCandidate(
            item: item,
            reason: reason,
            addedAt: addedAt ?? source.addedAt,
            newSeasonNumber: source.newSeasonNumber ?? newSeasonNumber,
            collectionTitle: source.collectionTitle ?? collectionTitle,
        )
    }
}

/// The candidates one server proposes.
struct ServerFeaturedCandidates: Hashable {
    let server: ServerIdentity
    let candidates: [FeaturedCandidate]
}

/// Seeds the daily draw, so the hero stays the same for a profile during a day.
struct FeaturedSeed: Hashable {
    let profileID: String
    let day: Int

    static func make(profileID: String, date: Date, calendar: Calendar = .current) -> FeaturedSeed {
        let start = calendar.startOfDay(for: date)
        return FeaturedSeed(profileID: profileID, day: Int((start.timeIntervalSince1970 / 86400).rounded()))
    }

    /// Stable across launches, unlike `Hasher`, which is seeded per process.
    func hash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(profileID)|\(day)|\(value)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
