import SwiftUI

struct LibraryRecommendedView: View {
    let library: Library
    let onSelectMedia: (MediaItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentUnavailableView(
                    "Recommended",
                    systemImage: "sparkles",
                    description: Text("We will surface hubs for \(library.title) here.")
                )
                .padding(.top, 24)
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    LibraryRecommendedView(
        library: Library(id: "1", title: "Movies", type: .movie),
        onSelectMedia: { _ in }
    )
}
