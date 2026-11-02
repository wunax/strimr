import SwiftUI

enum LibraryDetailTab: String, CaseIterable, Codable, Hashable, Identifiable {
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

    static func available(
        for library: Library,
        provider: MediaProvider,
        displaysCollections: Bool,
        displaysPlaylists: Bool,
    ) -> [LibraryDetailTab] {
        if provider == .jellyfin {
            return library.type == .collection || library.type == .playlist
                ? [.browse]
                : [.recommended, .browse]
        }
        if library.isShared {
            return [.browse]
        }
        return allCases.filter { tab in
            switch tab {
            case .collections:
                displaysCollections
            case .playlists:
                displaysPlaylists
            default:
                true
            }
        }
    }

    static func defaultTab(for library: Library) -> LibraryDetailTab {
        library.isShared || library.type == .collection || library.type == .playlist ? .browse : .recommended
    }

    /// Falls back to the default when the saved tab has since been hidden in settings.
    static func resolved(
        saved: LibraryDetailTab?,
        available: [LibraryDetailTab],
        library: Library,
    ) -> LibraryDetailTab {
        if let saved, available.contains(saved) {
            return saved
        }
        return defaultTab(for: library)
    }
}

/// `accessory` ends the row, after the tabs.
struct LibraryDetailTabPicker<Accessory: View>: View {
    @Binding private var selection: LibraryDetailTab
    let tabs: [LibraryDetailTab]
    private let accessory: Accessory

    init(
        selection: Binding<LibraryDetailTab>,
        tabs: [LibraryDetailTab],
        @ViewBuilder accessory: () -> Accessory,
    ) {
        _selection = selection
        self.tabs = tabs
        self.accessory = accessory()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.chipSpacing) {
                    ForEach(tabs) { tab in
                        tabButton(for: tab)
                            .id(tab)
                    }
                    accessory
                }
                .padding(focusLiftInsets)
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

    /// Room inside the scroll view so the focused chip is not clipped as it scales up.
    private var focusLiftInsets: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        #else
            EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        #endif
    }

    private func tabButton(for tab: LibraryDetailTab) -> some View {
        FilterChip(title: tab.title, systemImage: tab.systemImageName, isSelected: selection == tab) {
            withAnimation(Motion.crossfade) {
                selection = tab
            }
        }
    }
}

extension LibraryDetailTabPicker where Accessory == EmptyView {
    init(selection: Binding<LibraryDetailTab>, tabs: [LibraryDetailTab]) {
        self.init(selection: selection, tabs: tabs) { EmptyView() }
    }
}
