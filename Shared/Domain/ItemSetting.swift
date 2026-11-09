import Foundation

/// A per-item server setting offered as a choice in a list, such as the episode order of a series.
struct ItemSetting: Identifiable, Hashable, Sendable {
    struct Option: Hashable, Sendable {
        let value: String
        let label: String
    }

    let id: String
    let label: String
    let summary: String?
    var value: String
    let options: [Option]
}
