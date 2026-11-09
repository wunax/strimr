import Observation
import SwiftUI

/// A short result shown over the page without interrupting it, for outcomes that need no decision.
struct Toast: Identifiable {
    enum Style {
        case success
        case failure
    }

    let id = UUID()
    let style: Style
    let title: String
    var message: String?

    /// Failures stay longer since their message is read rather than glanced at.
    var duration: Duration {
        switch style {
        case .success: .seconds(3)
        case .failure: .seconds(5)
        }
    }
}

@MainActor
@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    func show(_ toast: Toast) {
        current = toast
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: toast.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
        AccessibilityNotification.Announcement([toast.title, toast.message].compactMap(\.self).joined(separator: ", "))
            .post()
    }

    /// Ignored when another toast replaced this one meanwhile.
    func dismiss(_ id: Toast.ID) {
        guard current?.id == id else { return }
        current = nil
    }
}

extension View {
    /// Shows the toasts set on `toast` through the window's toast host, then clears it.
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastForwarder(toast: toast))
    }
}

private struct ToastForwarder: ViewModifier {
    @Binding var toast: Toast?
    @Environment(ToastCenter.self) private var center: ToastCenter?

    func body(content: Content) -> some View {
        content.onChange(of: toast?.id, initial: true) {
            guard let toast else { return }
            self.toast = nil
            center?.show(toast)
        }
    }
}
