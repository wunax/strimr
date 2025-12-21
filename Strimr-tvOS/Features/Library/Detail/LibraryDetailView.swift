import SwiftUI

struct LibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    let library: Library
    let onSelectMedia: (MediaItem) -> Void

    @State private var viewModel = LibraryDetailViewModel()
    @State private var selectedTab: LibraryDetailTab = .recommended
    @FocusState private var focusedSidebarItem: LibraryDetailTab?

    init(
        library: Library,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            if selectedTab == .recommended, let heroMedia = viewModel.heroMedia {
                MediaHeroBackgroundView(media: heroMedia)
            }

            HStack(alignment: .center, spacing: 36) {
                sidebarView
                    .focusSection()
                contentView
                    .focusSection()
            }
            .ignoresSafeArea(edges: [.leading])
        }
    }

    private var contentView: some View {
        Group {
            switch selectedTab {
            case .recommended:
                LibraryTVRecommendedView(
                    viewModel: LibraryRecommendedViewModel(
                        library: library,
                        context: plexApiContext
                    ),
                    heroMedia: $viewModel.heroMedia,
                    onSelectMedia: onSelectMedia
                )
            case .browse:
                LibraryBrowseView(
                    viewModel: LibraryBrowseViewModel(
                        library: library,
                        context: plexApiContext
                    ),
                    onSelectMedia: onSelectMedia
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarView: some View {
        VStack {
            ForEach(LibraryDetailTab.allCases) { tab in
                sidebarButton(for: tab)
            }
        }
        .frame(maxWidth: sidebarWidth, maxHeight: .infinity)
        .padding(.leading, 36)
        .animation(.easeInOut(duration: 0.2), value: isSidebarFocused)
    }

    private func sidebarButton(for tab: LibraryDetailTab) -> some View {
        let isFocused = focusedSidebarItem == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImageName)
                if isSidebarFocused {
                    Text(tab.title)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
            .clipShape(Capsule())
        }
        .focused($focusedSidebarItem, equals: tab)
        .buttonStyle(.plain)
    }

    private var isSidebarFocused: Bool {
        focusedSidebarItem != nil
    }

    private var sidebarWidth: CGFloat {
        isSidebarFocused ? 240 : 72
    }
}

enum LibraryDetailTab: String, CaseIterable, Identifiable {
    case recommended
    case browse

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .recommended:
            return "library.detail.tab.recommended"
        case .browse:
            return "library.detail.tab.browse"
        }
    }

    var systemImageName: String {
        switch self {
        case .recommended:
            return "sparkles"
        case .browse:
            return "square.grid.2x2.fill"
        }
    }
}
