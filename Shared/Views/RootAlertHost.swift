import Observation
import SwiftUI

/// An alert shown from the root of the window rather than from the view that asked for it.
struct RootAlert: Identifiable {
    struct DestructiveAction {
        let title: String
        let perform: () -> Void
    }

    let id = UUID()
    let title: String
    let message: String
    var destructiveAction: DestructiveAction?
}

/// On iOS and tvOS, a view that held a context menu can no longer present an alert once the menu has closed, so
/// results that arrive after a menu action are shown from the root instead.
@MainActor
@Observable
final class RootAlertPresenter {
    var alert: RootAlert?
}

extension View {
    func rootAlertHost() -> some View {
        modifier(RootAlertHost())
    }
}

private struct RootAlertHost: ViewModifier {
    @State private var presenter = RootAlertPresenter()

    func body(content: Content) -> some View {
        content
            .environment(presenter)
            .alert(item: $presenter.alert) { alert in
                if let action = alert.destructiveAction {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .destructive(Text(action.title), action: action.perform),
                        secondaryButton: .cancel(),
                    )
                } else {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("common.actions.done")),
                    )
                }
            }
    }
}
