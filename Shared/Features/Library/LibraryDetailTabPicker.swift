import SwiftUI

enum LibraryDetailTab: String, CaseIterable, Hashable, Identifiable {
    case recommended
    case browse
    case collections
    case playlists

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .recommended:
            "library.detail.tab.recommended"
        case .browse:
            "library.detail.tab.browse"
        case .collections:
            "library.detail.tab.collections"
        case .playlists:
            "library.detail.tab.playlists"
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
        let isSelected = selection == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImageName)
                    .font(.subheadline.weight(.semibold))

                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.brandPrimary.opacity(0.18) : Color.gray.opacity(0.12)),
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? Color.brandPrimary : Color.gray.opacity(0.25),
                        lineWidth: 1,
                    )
            }
            .foregroundStyle(isSelected ? Color.brandPrimary : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
