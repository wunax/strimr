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

#if os(iOS)
    /// Underlined text tabs, so the library sections read as navigation rather than as filter chips.
    struct LibraryDetailTabBar: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Binding var selection: LibraryDetailTab
        let tabs: [LibraryDetailTab]
        @Namespace private var indicator

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(tabs) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(.horizontal, 16)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.strokeSubtle)
                    .frame(height: 1)
            }
            .accessibilityLabel(Text("library.detail.tabPicker"))
        }

        private func tabButton(for tab: LibraryDetailTab) -> some View {
            let isSelected = selection == tab
            return Button {
                withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                    selection = tab
                }
            } label: {
                Text(tab.title)
                    .font(.rowTitle)
                    .foregroundStyle(isSelected ? Color.textPrimary : .textSecondary)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Capsule()
                                .fill(.selectionAccent)
                                .frame(height: 3)
                                .matchedGeometryEffect(id: "indicator", in: indicator)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
#endif
