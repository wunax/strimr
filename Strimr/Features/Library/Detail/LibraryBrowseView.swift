import SwiftUI

struct LibraryBrowseView: View {
    let library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ContentUnavailableView(
                    "Browse",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("Explore filters, genres, and collections for \(library.title).")
                )
                .padding(.top, 24)
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    LibraryBrowseView(
        library: Library(id: "1", title: "Movies", type: .movie)
    )
}
