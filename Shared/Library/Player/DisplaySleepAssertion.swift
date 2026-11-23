import AetherEngine
import Foundation
#if os(macOS)
    import IOKit.pwr_mgt
#endif

/// Keeps the display awake while a video plays.
///
/// The engine's display layer asks for this itself, but on macOS that holds no power assertion, so the screen dimmed
/// and slept after the idle delay during playback. On iOS and tvOS the layer already keeps the screen on, so this
/// type does nothing there.
final class DisplaySleepAssertion {
    private(set) var isHeld = false
    #if os(macOS)
        private var assertionID = IOPMAssertionID(0)
    #endif

    /// Whether the assertion should be held after the engine reports `state`.
    /// Loading and seeking keep the current value, so a seek while playing does not let the display sleep.
    static func isHeld(after state: PlaybackState, current: Bool) -> Bool {
        switch state {
        case .playing:
            true
        case .loading, .seeking:
            current
        case .paused, .ended, .idle, .error:
            false
        }
    }

    func update(for state: PlaybackState) {
        setHeld(Self.isHeld(after: state, current: isHeld))
    }

    func release() {
        setHeld(false)
    }

    private func setHeld(_ held: Bool) {
        guard held != isHeld else { return }
        #if os(macOS)
            if held {
                let result = IOPMAssertionCreateWithName(
                    kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "Strimr video playback" as CFString,
                    &assertionID,
                )
                guard result == kIOReturnSuccess else { return }
            } else {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }
        #endif
        isHeld = held
    }

    deinit {
        #if os(macOS)
            if isHeld {
                IOPMAssertionRelease(assertionID)
            }
        #endif
    }
}
