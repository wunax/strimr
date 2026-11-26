import SwiftUI

/// The Explore tab on iOS and macOS: the rails of one source at a time, picked from the title menu.
@MainActor
struct ExploreView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ExploreSourceRegistry.self) private var registry
    @State private var viewModel: ExploreViewModel
    @State private var searchViewModel: ExploreSearchViewModel
    let onSelectItem: (ExploreItem) -> Void
    let onSelectRail: (ExploreRail) -> Void
    let onShowRequests: () -> Void

    init(
        viewModel: ExploreViewModel,
        searchViewModel: ExploreSearchViewModel,
        onSelectItem: @escaping (ExploreItem) -> Void,
        onSelectRail: @escaping (ExploreRail) -> Void,
        onShowRequests: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        _searchViewModel = State(initialValue: searchViewModel)
        self.onSelectItem = onSelectItem
        self.onSelectRail = onSelectRail
        self.onShowRequests = onShowRequests
    }

    var body: some View {
        @Bindable var searchViewModel = searchViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if searchViewModel.isActive {
                    searchContent
                } else {
                    railsContent
                }
            }
            .padding(.horizontal, LayoutMetrics.pageMargin)
            .padding(.vertical, 20)
        }
        .navigationTitle(registry.activeSource?.displayName ?? String(localized: "tabs.explore"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if registry.sources.count > 1 {
                    ToolbarItem(placement: sourcePickerPlacement) {
                        sourcePicker
                    }
                }
                if registry.activeSource?.id == .seerr {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onShowRequests) {
                            Label("seerr.requests.title", systemImage: "tray.full.fill")
                        }
                        .badge(viewModel.requestsBadgeCount)
                    }
                }
            }
            .task(id: activeSourceKey) {
                await viewModel.loadIfNeeded()
            }
            .task(id: SearchKey(query: searchViewModel.trimmedQuery, source: activeSourceKey)) {
                await searchViewModel.search()
            }
            .onAppear {
                Task { await viewModel.loadIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await viewModel.loadIfNeeded() }
            }
            .refreshable {
                if searchViewModel.isActive {
                    await searchViewModel.search()
                } else {
                    await viewModel.reload()
                }
            }
        #if os(iOS)
            .searchable(
                text: $searchViewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(searchPrompt),
            )
        #else
            .searchable(text: $searchViewModel.query, prompt: Text(searchPrompt))
        #endif
    }

    private struct SearchKey: Equatable {
        let query: String
        let source: ObjectIdentifier?
    }

    private var activeSourceKey: ObjectIdentifier? {
        registry.activeSource.map { ObjectIdentifier($0) }
    }

    private var searchPrompt: String {
        String(localized: "explore.search.prompt \(registry.activeSource?.displayName ?? "")")
    }

    private var sourcePickerPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .principal
        #else
            .navigation
        #endif
    }

    private var sourcePicker: some View {
        Menu {
            ForEach(registry.sources.map(\.id), id: \.self) { id in
                Button {
                    registry.select(id)
                } label: {
                    if id == registry.activeSource?.id {
                        Label(id.displayName, systemImage: "checkmark")
                    } else {
                        Text(id.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(registry.activeSource?.displayName ?? "")
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(Text("explore.source.pick"))
    }

    @ViewBuilder
    private var railsContent: some View {
        ForEach(viewModel.rails) { rail in
            MediaHubSection(title: rail.title, onViewAll: rail.hasMore ? { onSelectRail(rail) } : nil) {
                ExploreCarousel(
                    items: rail.items,
                    showsLabels: settingsManager.interface.showsCardLabels,
                    onSelect: onSelectItem,
                )
            }
        }

        if viewModel.isLoading, !viewModel.hasContent {
            ForEach(0 ..< 3, id: \.self) { _ in
                SectionSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
            }
        } else if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if !viewModel.hasContent {
            Text("explore.empty \(registry.activeSource?.displayName ?? "")")
                .foregroundStyle(.textSecondary)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(searchViewModel.results) { item in
                ExploreSearchRow(item: item) {
                    onSelectItem(item)
                }
            }
        }

        if searchViewModel.isSearching, searchViewModel.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let errorMessage = searchViewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if searchViewModel.hasSearched, searchViewModel.results.isEmpty {
            Text("explore.search.empty \(searchViewModel.trimmedQuery)")
                .foregroundStyle(.textSecondary)
        }
    }
}
