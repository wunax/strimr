@testable import Strimr
import Testing

@MainActor
struct ToastCenterTests {
    @Test func `show replaces the current toast`() {
        let center = ToastCenter()
        center.show(Toast(style: .success, title: "First"))
        let second = Toast(style: .failure, title: "Second", message: "Details")
        center.show(second)

        #expect(center.current?.id == second.id)
    }

    @Test func `dismissing A replaced toast keeps the new one`() {
        let center = ToastCenter()
        let first = Toast(style: .success, title: "First")
        let second = Toast(style: .success, title: "Second")
        center.show(first)
        center.show(second)

        center.dismiss(first.id)

        #expect(center.current?.id == second.id)
    }

    @Test func `dismissing the current toast clears it`() {
        let center = ToastCenter()
        let toast = Toast(style: .failure, title: "Failed")
        center.show(toast)

        center.dismiss(toast.id)

        #expect(center.current == nil)
    }

    @Test func `failures stay longer than successes`() {
        #expect(Toast(style: .failure, title: "").duration > Toast(style: .success, title: "").duration)
    }
}
