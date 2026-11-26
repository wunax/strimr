import SwiftUI
import UIKit

/// The Explore tab on tvOS: a hero describing the focused card, the source chips, then the rails of that source.
@MainActor
struct ExploreView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(ExploreSourceRegistry.self) private var registry
    @State private var viewModel: ExploreViewModel
    @State private var focusModel = ExploreFocusModel()
    @FocusState private var focusedRail: String?
    let onSelectItem: (ExploreItem) -> Void
    let onSelectRail: (ExploreRail) -> Void
    let onShowRequests: () -> Void

    init(
        viewModel: ExploreViewModel,
        onSelectItem: @escaping (ExploreItem) -> Void,
        onSelectRail: @escaping (ExploreRail) -> Void,
        onShowRequests: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectItem = onSelectItem
        self.onSelectRail = onSelectRail
        self.onShowRequests = onShowRequests
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    if let heroItem {
                        ZStack(alignment: .topLeading) {
                            ExploreHeroBackgroundView(item: heroItem)
                            hero(for: heroItem)
                                .frame(
                                    maxWidth: proxy.size.width * 0.60,
                                    maxHeight: .infinity,
                                    alignment: .topLeading,
                                )
                        }
                    }

                    // Always the lower part of the screen, as on the library hero: the rails never jump when the
                    // hero arrives, and the actions stay reachable while a source loads or fails.
                    content
                        .frame(height: proxy.size.height * 0.60)
                }
            }
        }
        .environment(focusModel)
        .task(id: activeSourceKey) {
            focusModel.focusedItem = nil
            await viewModel.loadIfNeeded()
            updateInitialFocus()
        }
        .onAppear {
            Task { await viewModel.loadIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.loadIfNeeded() }
        }
        .onChange(of: viewModel.rails.first?.items.first?.id) { _, _ in
            updateInitialFocus()
        }
    }

    /// Seerr items keep the hero the Discover tab always had, with its runtime, genres and rating.
    @ViewBuilder
    private func hero(for item: ExploreItem) -> some View {
        if let media = item.seerrMedia {
            SeerrHeroContentView(media: media)
        } else {
            ExploreHeroContentView(item: item)
        }
    }

    private var activeSourceKey: ObjectIdentifier? {
        registry.activeSource.map { ObjectIdentifier($0) }
    }

    private var heroItem: ExploreItem? {
        focusModel.focusedItem ?? viewModel.rails.first?.items.first
    }

    private func updateInitialFocus() {
        guard focusModel.focusedItem == nil else { return }
        focusModel.focusedItem = viewModel.rails.first?.items.first
    }

    /// The actions lead the rails inside their scroll view, so moving up from any rail stays in one focus flow.
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                actions
                railsContent
            }
            .padding(.top, 16)
            .padding(.trailing, LayoutMetrics.pageMargin)
        }
        .scrollsFocusedRowToTop(focusedRail)
    }

    private var actions: some View {
        HStack(spacing: 16) {
            NavigationLink {
                ExploreSearchView(
                    viewModel: ExploreSearchViewModel(registry: registry),
                    onSelectItem: onSelectItem,
                )
            } label: {
                Label("tabs.search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .actionButtonStyle(.primary)

            if registry.activeSource?.id == .seerr {
                Button(action: onShowRequests) {
                    Label(
                        viewModel.requestsBadgeCount > 0
                            ? String(localized: "seerr.manageRequests.short \(viewModel.requestsBadgeCount)")
                            : String(localized: "seerr.requests.title"),
                        systemImage: "tray.full.fill",
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .actionButtonStyle(.secondary)
            }

            if registry.sources.count > 1 {
                sourcePicker
            }
        }
        .frame(maxWidth: actionsMaxWidth, alignment: .leading)
        // Full width so moving up from the right side of a rail still lands on an action, not on the tab bar.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private var actionsMaxWidth: CGFloat {
        let buttonCount = (registry.activeSource?.id == .seerr ? 2 : 1) + (registry.sources.count > 1 ? 1 : 0)
        return CGFloat(buttonCount) * 360
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
            Label(
                registry.activeSource?.displayName ?? "",
                systemImage: registry.activeSource?.id.systemImage ?? "safari",
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .actionButtonStyle(.secondary)
        .accessibilityLabel(Text("explore.source.pick"))
    }

    @ViewBuilder
    private var railsContent: some View {
        ForEach(viewModel.rails) { rail in
            MediaHubSection(title: rail.title) {
                ExploreCarousel(
                    items: rail.items,
                    showsLabels: settingsManager.interface.showsCardLabels,
                    onViewAll: rail.hasMore ? { onSelectRail(rail) } : nil,
                    onSelect: onSelectItem,
                )
            }
            .id(rail.id)
            .focused($focusedRail, equals: rail.id)
        }

        if viewModel.isLoading, !viewModel.hasContent {
            RailsSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
        } else if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if !viewModel.hasContent {
            Text("explore.empty \(registry.activeSource?.displayName ?? "")")
                .foregroundStyle(.textSecondary)
        }
    }
}

/// Searches the active source.
struct ExploreSearchView: View {
    @Environment(ExploreSourceRegistry.self) private var registry
    @State private var viewModel: ExploreSearchViewModel
    let onSelectItem: (ExploreItem) -> Void

    init(viewModel: ExploreSearchViewModel, onSelectItem: @escaping (ExploreItem) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectItem = onSelectItem
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    resultsContent
                }
                .padding(.vertical, 16)
            }
        }
        .searchable(text: $viewModel.query, prompt: Text(prompt))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("tabs.search")
        .task(id: viewModel.trimmedQuery) {
            await viewModel.search()
        }
    }

    private var prompt: String {
        String(localized: "explore.search.prompt \(registry.activeSource?.displayName ?? "")")
    }

    @ViewBuilder
    private var resultsContent: some View {
        if !viewModel.isActive {
            ContentUnavailableView("tabs.search", systemImage: "magnifyingglass", description: Text(prompt))
                .frame(maxWidth: .infinity)
        } else if viewModel.isSearching, viewModel.results.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.hasSearched, viewModel.results.isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "film.stack.fill",
                description: Text("explore.search.empty \(viewModel.trimmedQuery)"),
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 48) {
                ForEach(viewModel.results) { item in
                    ExploreSearchRow(item: item) {
                        onSelectItem(item)
                    }
                }
            }
            .focusSection()
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: 48),
            GridItem(.flexible(minimum: 320), spacing: 48),
        ]
    }
}

struct ExploreHeroBackgroundView: View {
    let item: ExploreItem

    var body: some View {
        HeroBackdropView(key: item.id, load: loadBackdrop)
    }

    private func loadBackdrop() async -> HeroBackdrop {
        guard let url = item.backdropURL ?? item.posterURL else { return HeroBackdrop() }
        let resource = ArtworkResource.url(url)
        await ArtworkResourceView.preload(resource)
        guard let colors = try? await ImageCornerColorSampler.colors(from: resource), colors.count == 4 else {
            return HeroBackdrop(resource: resource)
        }
        return HeroBackdrop(resource: resource, colors: colors)
    }
}

/// Same layout as the library hero: a title in the room of a logo, then facts and summary.
struct ExploreHeroContentView: View {
    let item: ExploreItem
    private let summaryLineLimit = 3

    var body: some View {
        HeroContentTransitionView(item: item) { item in
            VStack(alignment: .leading, spacing: 12) {
                // Fixed height so a two-line title never moves what follows during hero transitions.
                Text(item.title)
                    .font(.heroTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: LayoutMetrics.heroLogoMaxSize.height,
                        maxHeight: LayoutMetrics.heroLogoMaxSize.height,
                        alignment: .bottomLeading,
                    )
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 24) {
                    MediaFactsLine(facts: MediaFacts(tokens: item.year.map { [String($0)] } ?? []))
                    if let status = item.seerrStatus {
                        SeerrAvailabilityBadgeView(status: status, showsLabel: true, isDownloading: false)
                    }
                }

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(summaryLineLimit)
                        .frame(
                            minHeight: UIFont.systemFont(ofSize: 26).lineHeight * CGFloat(summaryLineLimit),
                            alignment: .top,
                        )
                }
            }
        }
    }
}
