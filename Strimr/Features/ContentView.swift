import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionCoordinator: SessionCoordinator

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            
            switch sessionCoordinator.status {
            case .hydrating:
                ProgressView("Loading…")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView()
            case .needsServerSelection:
                SelectServerView(sessionCoordinator: sessionCoordinator)
            case .ready:
                Text("App ready placeholder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionCoordinator())
}
