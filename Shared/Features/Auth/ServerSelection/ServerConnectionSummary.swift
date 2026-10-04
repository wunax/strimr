import SwiftUI

/// How a Plex server is reached, from its first advertised connection.
struct ServerConnectionSummary: View {
    let server: PlexCloudResource

    var body: some View {
        if let connection = server.connections?.first {
            if connection.isLocal {
                Text("serverSelection.connection.localFormat \(connection.address)")
            } else if connection.isRelay {
                Text("serverSelection.connection.relay")
            } else {
                Text(connection.address)
            }
        } else {
            Text("serverSelection.connection.unavailable")
        }
    }
}
