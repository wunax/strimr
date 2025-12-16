import SwiftUI

enum MoreRoute: Hashable {
    case settings
}

@MainActor
struct MoreView: View {
    var onSwitchProfile: () -> Void = {}
    var onSwitchServer: () -> Void = {}
    var onLogout: () -> Void = {}

    var body: some View {
        List {
            Section {
                NavigationLink(value: MoreRoute.settings) {
                    Label("Settings", systemImage: "gearshape.fill")
                }

                Button(action: onSwitchProfile) {
                    Label("Switch Profile", systemImage: "person.2.circle")
                }
                .buttonStyle(.plain)

                Button(action: onSwitchServer) {
                    Label("Switch Server", systemImage: "server.rack")
                }
                .buttonStyle(.plain)

                Button(action: onLogout) {
                    Label("Log Out", systemImage: "arrow.backward.circle")
                }
                .buttonStyle(.plain)
                .tint(.red)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("More")
    }
}

#Preview {
    NavigationStack {
        MoreView()
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .settings:
                    EmptyView()
                }
            }
    }
}
