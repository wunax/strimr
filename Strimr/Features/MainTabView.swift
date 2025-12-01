import SwiftUI

struct MainTabView: View {
    @StateObject private var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $coordinator.tab) {
            NavigationStack(path: coordinator.pathBinding(for: .home)) {
                HomeView(
                    viewModel: HomeViewModel(),
                    onSelectMedia: coordinator.showMediaDetail
                )
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .tabItem { Label("tabs.home", systemImage: "house.fill") }
            .tag(MainCoordinator.Tab.home)

            NavigationStack(path: coordinator.pathBinding(for: .search)) {
                SearchView()
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem { Label("tabs.search", systemImage: "magnifyingglass") }
            .tag(MainCoordinator.Tab.search)

            NavigationStack(path: coordinator.pathBinding(for: .library)) {
                LibraryView()
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem { Label("tabs.libraries", systemImage: "rectangle.stack.fill") }
            .tag(MainCoordinator.Tab.library)
        }
        .tint(.brandPrimary)
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
            if let media = coordinator.selectedMedia {
                PlayerView()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case .mediaDetail:
            MediaDetailView()
        }
    }
}

#Preview {
    MainTabView()
}
