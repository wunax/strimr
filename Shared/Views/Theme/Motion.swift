import SwiftUI

enum Motion {
    static let focus: Animation = .easeOut(duration: 0.12)
    static let focusScale: Animation = .spring(response: 0.35, dampingFraction: 0.85)
    /// Outgoing content fades rather than slides.
    static let crossfade: Animation = .easeInOut(duration: 0.2)
    static let hero: Animation = .easeInOut(duration: 0.24)
    /// Slow enough that a backdrop changing on its own does not catch the eye like a transition would.
    static let ambient: Animation = .easeInOut(duration: 1.2)
    /// Player controls fading in and out over the video.
    static let controls: Animation = .easeInOut(duration: 0.35)
    /// Panels and bars sliding over the video, such as the player info panel or the tvOS player settings.
    static let panel: Animation = .smooth(duration: 0.3)
    static let heroFocusDelay: Duration = .milliseconds(150)

    private static let fades: [Animation] = [crossfade, hero, ambient, controls]

    /// Fades survive Reduce Motion; every other movement is dropped.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        guard reduceMotion else { return animation }
        return fades.contains(animation) ? animation : nil
    }
}
