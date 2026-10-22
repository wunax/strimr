import SwiftUI

enum Motion {
    static let focus: Animation = .easeOut(duration: 0.12)
    static let focusScale: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    /// Outgoing content fades rather than slides.
    static let crossfade: Animation = .easeInOut(duration: 0.2)
    static let hero: Animation = .easeInOut(duration: 0.24)
    static let heroFocusDelay: Duration = .milliseconds(150)
    /// Scrolling or reflowing a page, eased like the system's focus scrolling.
    static let pageScroll: Animation = .smooth(duration: 0.8)

    private static let fades: [Animation] = [crossfade, hero]

    /// Fades survive Reduce Motion; every other movement is dropped.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        guard reduceMotion else { return animation }
        return fades.contains(animation) ? animation : nil
    }
}
