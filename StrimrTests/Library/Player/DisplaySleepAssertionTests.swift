import AetherEngine
import Foundation
@testable import Strimr
import Testing
#if os(macOS)
    import IOKit.pwr_mgt
#endif

struct DisplaySleepAssertionTests {
    @Test(arguments: [false, true])
    func `playing holds and stopped states release`(current: Bool) {
        #expect(DisplaySleepAssertion.isHeld(after: .playing, current: current))
        #expect(!DisplaySleepAssertion.isHeld(after: .paused, current: current))
        #expect(!DisplaySleepAssertion.isHeld(after: .ended, current: current))
        #expect(!DisplaySleepAssertion.isHeld(after: .idle, current: current))
        #expect(!DisplaySleepAssertion.isHeld(after: .error("failed"), current: current))
    }

    @Test(arguments: [false, true])
    func `loading and seeking keep the current value`(current: Bool) {
        #expect(DisplaySleepAssertion.isHeld(after: .loading, current: current) == current)
        #expect(DisplaySleepAssertion.isHeld(after: .seeking, current: current) == current)
    }

    @Test
    func `follows play pause seek and release`() {
        let assertion = DisplaySleepAssertion()
        assertion.update(for: .loading)
        #expect(!assertion.isHeld)
        assertion.update(for: .playing)
        #expect(assertion.isHeld)
        assertion.update(for: .seeking)
        #expect(assertion.isHeld)
        assertion.update(for: .paused)
        #expect(!assertion.isHeld)
        assertion.update(for: .playing)
        assertion.release()
        #expect(!assertion.isHeld)
    }

    #if os(macOS)
        @Test
        func `holds a display sleep assertion on mac`() {
            let baseline = displaySleepAssertionCount()
            var assertion: DisplaySleepAssertion? = DisplaySleepAssertion()
            assertion?.update(for: .playing)
            #expect(displaySleepAssertionCount() == baseline + 1)
            assertion?.update(for: .paused)
            #expect(displaySleepAssertionCount() == baseline)
            assertion?.update(for: .playing)
            #expect(displaySleepAssertionCount() == baseline + 1)
            assertion = nil
            #expect(displaySleepAssertionCount() == baseline)
        }

        /// The display-sleep assertions this test process holds, as the system sees them.
        private func displaySleepAssertionCount() -> Int {
            var byProcess: Unmanaged<CFDictionary>?
            guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
                  let all = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
            else { return 0 }
            let own = all[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? []
            return own.count {
                $0[kIOPMAssertionTypeKey] as? String == kIOPMAssertPreventUserIdleDisplaySleep
            }
        }
    #endif
}
