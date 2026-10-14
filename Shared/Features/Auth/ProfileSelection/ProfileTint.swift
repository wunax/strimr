import SwiftUI

/// Per-profile accent, picked from a curated palette so every profile keeps the same color across launches.
enum ProfileTint {
    static let palette: [Color] = [
        Color(red: 0.88, green: 0.20, blue: 0.37),
        Color(red: 0.94, green: 0.39, blue: 0.24),
        Color(red: 0.91, green: 0.64, blue: 0.23),
        Color(red: 0.18, green: 0.71, blue: 0.49),
        Color(red: 0.12, green: 0.65, blue: 0.72),
        Color(red: 0.24, green: 0.48, blue: 0.94),
        Color(red: 0.42, green: 0.36, blue: 0.89),
        Color(red: 0.69, green: 0.31, blue: 0.84),
    ]

    static func color(for profileID: String) -> Color {
        palette[index(for: profileID)]
    }

    /// FNV-1a, because `hashValue` is reseeded on every launch.
    static func index(for profileID: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in profileID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(palette.count))
    }
}
