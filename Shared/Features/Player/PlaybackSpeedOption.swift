import Foundation

struct PlaybackSpeedOption: Identifiable, Hashable {
    let rate: Float

    var id: Float {
        rate
    }

    /// Stable, locale-independent numeric representation used for localization interpolation.
    var valueText: String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(rate))
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}

enum PlaybackSpeedOptions {
    static let all: [PlaybackSpeedOption] = [
        PlaybackSpeedOption(rate: 0.5),
        PlaybackSpeedOption(rate: 0.75),
        PlaybackSpeedOption(rate: 1.0),
        PlaybackSpeedOption(rate: 1.25),
        PlaybackSpeedOption(rate: 1.5),
        PlaybackSpeedOption(rate: 1.75),
        PlaybackSpeedOption(rate: 2.0),
    ]
}
