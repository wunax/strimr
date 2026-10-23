import SwiftUI

enum LibraryDetailTab: String, CaseIterable, Hashable, Identifiable {
    case recommended
    case browse
    case collections
    case playlists

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recommended:
            String(localized: "library.detail.tab.recommended")
        case .browse:
            String(localized: "library.detail.tab.browse")
        case .collections:
            String(localized: "library.detail.tab.collections")
        case .playlists:
            String(localized: "library.detail.tab.playlists")
        }
    }

    var systemImageName: String {
        switch self {
        case .recommended:
            "sparkles"
        case .browse:
            "square.grid.2x2.fill"
        case .collections:
            "rectangle.stack.fill"
        case .playlists:
            "music.note.list"
        }
    }
}

struct LibraryDetailTabPicker: View {
    @Binding private var selection: LibraryDetailTab
    let tabs: [LibraryDetailTab]

    init(
        selection: Binding<LibraryDetailTab>,
        tabs: [LibraryDetailTab],
    ) {
        _selection = selection
        self.tabs = tabs
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        tabButton(for: tab)
                            .id(tab)
                    }
                }
                .padding(.horizontal, 2)
            }
            .mouseDragScrolling()
            .accessibilityLabel(Text("library.detail.tabPicker"))
            .onChange(of: selection) { _, newSelection in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newSelection, anchor: .center)
                }
            }
        }
    }

    private func tabButton(for tab: LibraryDetailTab) -> some View {
        FilterChip(title: tab.title, systemImage: tab.systemImageName, isSelected: selection == tab) {
            withAnimation(Motion.crossfade) {
                selection = tab
            }
        }
    }
}
