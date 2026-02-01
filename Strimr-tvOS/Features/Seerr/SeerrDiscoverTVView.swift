import SwiftUI

@MainActor
struct SeerrDiscoverTVView: View {
    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            ContentUnavailableView(
                "tabs.discover",
                systemImage: "sparkles",
                description: Text("common.empty.nothingToShow")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
