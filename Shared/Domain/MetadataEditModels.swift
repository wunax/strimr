import Foundation

/// A metadata field the server administrator can edit.
enum MetadataField: String, CaseIterable, Hashable, Sendable {
    case title
    case sortTitle
    case originalTitle
    /// Stored as `yyyy-MM-dd`, empty when unknown.
    case releaseDate
    case contentRating
    case studio
    case tagline
    case summary
    case genres
    case labels
    case directors
    case writers
    case countries

    var isList: Bool {
        switch self {
        case .genres, .labels, .directors, .writers, .countries: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .title: String(localized: "media.metadata.field.title")
        case .sortTitle: String(localized: "media.metadata.field.sortTitle")
        case .originalTitle: String(localized: "media.metadata.field.originalTitle")
        case .releaseDate: String(localized: "media.metadata.field.releaseDate")
        case .contentRating: String(localized: "media.metadata.field.contentRating")
        case .studio: String(localized: "media.metadata.field.studio")
        case .tagline: String(localized: "media.metadata.field.tagline")
        case .summary: String(localized: "media.metadata.field.summary")
        case .genres: String(localized: "media.metadata.field.genres")
        case .labels: String(localized: "media.metadata.field.labels")
        case .directors: String(localized: "media.metadata.field.directors")
        case .writers: String(localized: "media.metadata.field.writers")
        case .countries: String(localized: "media.metadata.field.countries")
        }
    }

    /// Seasons are left out: only their title and summary could be edited.
    static func editableFields(for type: MediaKind) -> [MetadataField] {
        switch type {
        case .movie: allCases
        case .series: allCases.filter { $0 != .directors && $0 != .writers }
        case .episode: [.title, .releaseDate, .summary, .directors, .writers]
        default: []
        }
    }
}

/// The editable metadata of an item, compared with the version loaded from the server to save only what changed.
struct MetadataDraft: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        case plex(sectionID: String, type: Int)
        /// The item as Jellyfin sent it: Jellyfin replaces the whole item on save and clears any missing field.
        case jellyfin(item: Data)
    }

    let fields: [MetadataField]
    var values: [MetadataField: String]
    var lists: [MetadataField: [String]]
    var lockedFields: Set<MetadataField>
    /// Fields whose lock the server keeps.
    let lockableFields: Set<MetadataField>
    /// Fields the server locks together, such as the directors and writers Jellyfin locks as its cast.
    var sharedLocks: [Set<MetadataField>] = []
    /// Choices offered for the content rating; empty when it is free text.
    var contentRatingOptions: [String] = []
    let payload: Payload

    func value(_ field: MetadataField) -> String {
        values[field] ?? ""
    }

    func list(_ field: MetadataField) -> [String] {
        lists[field] ?? []
    }

    func isLocked(_ field: MetadataField) -> Bool {
        lockedFields.contains(field)
    }

    /// Locks the field, or the next refresh from the providers would overwrite it.
    mutating func setValue(_ value: String, for field: MetadataField) {
        guard self.value(field) != value else { return }
        values[field] = value
        setLocked(true, for: field)
    }

    mutating func setList(_ list: [String], for field: MetadataField) {
        guard self.list(field) != list else { return }
        lists[field] = list
        setLocked(true, for: field)
    }

    /// Ignores blank and duplicate entries.
    mutating func addListEntry(_ entry: String, to field: MetadataField) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = list(field)
        guard !trimmed.isEmpty,
              !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        setList(current + [trimmed], for: field)
    }

    mutating func setLocked(_ locked: Bool, for field: MetadataField) {
        guard lockableFields.contains(field) else { return }
        let group = sharedLocks.first { $0.contains(field) } ?? [field]
        if locked {
            lockedFields.formUnion(group)
        } else {
            lockedFields.subtract(group)
        }
    }

    func changedFields(from original: MetadataDraft) -> [MetadataField] {
        fields.filter { field in
            field.isList ? list(field) != original.list(field) : value(field) != original.value(field)
        }
    }

    /// Fields whose lock changed while their value did not.
    func lockChangedFields(from original: MetadataDraft) -> [MetadataField] {
        let changed = Set(changedFields(from: original))
        return fields.filter { !changed.contains($0) && isLocked($0) != original.isLocked($0) }
    }

    func hasChanges(from original: MetadataDraft) -> Bool {
        !changedFields(from: original).isEmpty || !lockChangedFields(from: original).isEmpty
    }
}

enum MetadataDate {
    /// `yyyy-MM-dd` in UTC, the format of Plex and of the date part of Jellyfin dates.
    static func date(from value: String) -> Date? {
        try? Date(value, strategy: strategy)
    }

    static func string(from date: Date) -> String {
        date.formatted(strategy)
    }

    private static let strategy = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
}
