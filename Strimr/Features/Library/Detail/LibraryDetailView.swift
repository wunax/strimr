import SwiftUI

struct LibraryDetailView: View {
    let library: Library
    let onSelectMedia: (MediaItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library tab", selection: $selectedTab) {
                ForEach(LibraryDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Group {
                switch selectedTab {
                case .recommended:
                    LibraryRecommendedView(
                        library: library,
                        onSelectMedia: onSelectMedia
                    )
                case .browse:
                    LibraryBrowseView(library: library)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(library.title)
        .toolbarTitleDisplayMode(.inline)
    }
}

enum LibraryDetailTab: String, CaseIterable, Identifiable {
    case recommended
    case browse

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recommended:
            return "Recommended"
        case .browse:
            return "Browse"
        }
    }
}

#Preview {
    NavigationStack {
        LibraryDetailView(
            library: Library(id: "1", title: "Movies", type: .movie),
            onSelectMedia: { _ in }
        )
    }
}
