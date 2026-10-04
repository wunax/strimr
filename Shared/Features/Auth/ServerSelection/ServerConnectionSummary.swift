import SwiftUI

/// Result of testing a Plex server's connections during server selection.
struct ServerConnectionSummary: View {
    let state: ServerSelectionViewModel.ProbeState?

    var body: some View {
        switch state {
        case .testing, nil:
            Text("serverSelection.probe.testing")
                .foregroundStyle(.secondary)
        case let .reachable(kind?):
            Text(kind.title)
                .foregroundStyle(kind == .relay ? Color.orange : Color.green)
        case .reachable(nil):
            Text("settings.accounts.status.ready")
                .foregroundStyle(.green)
        case .unreachable:
            Text("settings.accounts.status.unreachable")
                .foregroundStyle(.orange)
        }
    }
}
