import SwiftUI

/// The one-time update of the session could not finish; the previous session is kept and the update is retried.
struct MigrationFailedView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        ContentUnavailableView {
            Label("migration.failed.title", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("migration.failed.message")
        } actions: {
            Button("common.actions.retry") {
                Task { await sessionManager.hydrate() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
    }
}
