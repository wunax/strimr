import SwiftUI

struct LibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended

    var body: some View {
        VStack(spacing: 0) {
            Picker("library.detail.tabPicker", selection: $selectedTab) {
                ForEach(availableTabs) { tab in
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
                        viewModel: LibraryRecommendedViewModel(
                            library: library,
                            context: plexApiContext,
                        ),
                        onSelectMedia: onSelectMedia,
                    )
                case .browse:
                    LibraryBrowseView(
                        viewModel: LibraryBrowseViewModel(
                            library: library,
                            context: plexApiContext,
                            settingsManager: settingsManager,
                        ),
                        onSelectMedia: onSelectMedia,
                    )
                case .collections:
                    LibraryCollectionsView(
                        viewModel: LibraryCollectionsViewModel(
                            library: library,
                            context: plexApiContext,
                        ),
                        onSelectMedia: onSelectMedia,
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(library.title)
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: settingsManager.interface.displayCollections) { _, displayCollections in
            if !displayCollections, selectedTab == .collections {
                selectedTab = .recommended
            }
        }
    }

    private var availableTabs: [LibraryDetailTab] {
        settingsManager.interface.displayCollections
            ? LibraryDetailTab.allCases
            : LibraryDetailTab.allCases.filter { $0 != .collections }
    }
}

enum LibraryDetailTab: String, CaseIterable, Identifiable {
    case recommended
    case browse
    case collections

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
        }
    }
}
