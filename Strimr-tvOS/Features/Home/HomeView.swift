import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(ServerRegistry.self) private var registry
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.mediaCardActions) private var mediaCardActions
    @Environment(MediaFocusModel.self) private var focusModel
    @EnvironmentObject private var coordinator: MainCoordinator

    @State var viewModel: HomeViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var heroMode: HomeHeroMode = .showcase
    @State private var currentSlideID: MediaIdentity?
    @State private var heroFocusChangedAt = Date.distantPast
    @State private var autoAdvanceRestart = 0
    @State private var autoAdvanceStartedAt: Date?
    @State private var isZoomedIn = false
    @FocusState private var focusedHeroButton: HomeHeroButton?

    private static let autoAdvanceInterval: Duration = .seconds(8)
    private static let showcaseRowsTop: CGFloat = 0.85
    private static let browsingRowsTop: CGFloat = 0.40

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            // One layout with or without the showcase, so the rows keep their focus when the hero comes or goes.
            if currentSlide != nil || displayedHeroMedia != nil {
                heroLayout(slide: currentSlide)
            } else {
                emptyState
            }
        }
        .environment(\.reloadAfterPlaylistChange) { server in
            Task { await viewModel.refresh(server: server) }
        }
        .task {
            await viewModel.load()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.refreshPeriodically()
        }
        .task(id: seerrStore.isLoggedIn) {
            viewModel.seerrBaseURL = seerrStore.isLoggedIn ? seerrStore.baseURLString.flatMap(URL.init(string:)) : nil
        }
        .onChange(of: settingsManager.interface.homeHero) {
            viewModel.heroSettingsChanged()
        }
        .onChange(of: settingsManager.interface.homeHeroIncludesTrending) {
            viewModel.heroSettingsChanged()
        }
        .onChange(of: visibleHeroMediaIDs) { _, _ in
            updateInitialFocus()
        }
        .onChange(of: viewModel.heroSlides) { _, slides in
            if let currentSlideID, !slides.contains(where: { $0.id == currentSlideID }) {
                self.currentSlideID = slides.first?.id
            }
            if slides.isEmpty {
                heroMode = .browsing
            }
        }
        .background {
            CardFocusObserver {
                setHeroMode(.browsing)
            }
        }
        .onChange(of: focusedHeroButton) { previous, button in
            if button == .pageBack {
                // Only a press left from Play pages back; focus coming up from the rows just lands on Play.
                if previous == .play {
                    showSlide(at: currentIndex - 1)
                }
                focusedHeroButton = .play
                return
            }
            heroFocusChangedAt = Date()
            autoAdvanceRestart += 1
            if button != nil {
                setHeroMode(.showcase)
            }
        }
        .onAppear {
            updateInitialFocus()
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: viewModel.contentRevisions) {
            viewModel.refreshAfterContentChanges()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    // MARK: - Hero

    private var slides: [HomeHeroSlide] {
        viewModel.heroSlides
    }

    private var currentIndex: Int {
        currentSlideID.flatMap { id in slides.firstIndex { $0.id == id } } ?? 0
    }

    private var currentSlide: HomeHeroSlide? {
        slides.isEmpty ? nil : slides[currentIndex]
    }

    private func heroLayout(slide: HomeHeroSlide?) -> some View {
        GeometryReader { proxy in
            let showcased = heroMode == .showcase ? slide : nil
            let isShowcase = showcased != nil
            ZStack(alignment: .topLeading) {
                if let media = showcased?.media ?? displayedHeroMedia ?? slide?.media {
                    // Drifts slowly in then out from one page to the next, so a new page never snaps the zoom back.
                    MediaHeroBackgroundView(media: media)
                        .scaleEffect(isShowcase && isZoomedIn && !reduceMotion ? 1.04 : 1, anchor: .topTrailing)
                }

                Group {
                    if let showcased {
                        // Sits a little below the middle of the room above the buttons: off the tab bar, and close
                        // enough to the buttons that they read as its own.
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)
                            HomeShowcaseContentView(slide: showcased, index: currentIndex, count: slides.count)
                            Spacer(minLength: 80)
                                .frame(maxHeight: 130)
                        }
                        .frame(height: rowsTop(in: proxy, isShowcase: true) - Self.actionsHeight)
                        .transition(.opacity.combined(with: .offset(y: -40)))
                    } else if let media = displayedHeroMedia {
                        MediaHeroContentView(media: media)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: proxy.size.width * 0.60, alignment: .topLeading)

                if let slide {
                    // Padding rather than offset: focus moves by the laid out frames.
                    heroActions(slide: slide, isShowcase: isShowcase)
                        .padding(.top, rowsTop(in: proxy, isShowcase: isShowcase) - Self.actionsHeight)
                }

                // The section stops at the rows: after the padding it would cover the hero's buttons and take
                // every move towards them.
                homeContent
                    .frame(height: proxy.size.height * 0.60)
                    .focusSection()
                    .padding(.top, rowsTop(in: proxy, isShowcase: isShowcase))
            }
        }
        .onChange(of: slide?.id, initial: true) {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 8)) {
                isZoomedIn.toggle()
            }
        }
        .defaultFocus($focusedHeroButton, .play)
        .task(id: autoAdvanceKey) {
            await autoAdvance()
        }
        .task(id: slides.indices.contains(currentIndex + 1) ? slides[currentIndex + 1].id : slides.first?.id) {
            await prefetchNextBackdrop()
        }
    }

    private static let actionsHeight: CGFloat = 150

    private func rowsTop(in proxy: GeometryProxy, isShowcase: Bool) -> CGFloat {
        proxy.size.height * (isShowcase ? Self.showcaseRowsTop : Self.browsingRowsTop)
    }

    /// Kept in the hierarchy while browsing, transparent, so moving up from the first row comes back to the hero.
    private func heroActions(slide: HomeHeroSlide, isShowcase: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 0) {
                if settingsManager.interface.tabBarPlacement == .sidebar, slides.count > 1 {
                    pageBackStop
                }
                HomeShowcaseActions(
                    slide: slide,
                    focusedButton: $focusedHeroButton,
                    onPlay: { mediaCardActions?.play(slide.media, false) },
                    onDetails: { onSelectMedia(.playable(slide.media)) },
                )
                .onMoveCommand(perform: handleHeroMove)
            }

            if slides.count > 1 {
                HomeShowcasePageIndicator(
                    index: currentIndex,
                    count: slides.count,
                    autoAdvanceStartedAt: autoAdvanceStartedAt,
                    autoAdvanceInterval: Self.autoAdvanceInterval,
                )
                .frame(maxWidth: .infinity)
            }
        }
        // Full width, so moving up from any card of the first row lands on the buttons rather than the tab bar.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        // Just above the 0.01 alpha under which tvOS stops giving focus to a view.
        .opacity(isShowcase ? 1 : 0.02)
        .accessibilityHidden(!isShowcase)
    }

    /// Sits between Play and the sidebar so that left from Play reaches it instead of opening the sidebar. The sidebar
    /// stays a press of Menu, or left from the first card of a row, away.
    private var pageBackStop: some View {
        Button {} label: {
            Color.clear.frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        // Just above the 0.01 alpha under which tvOS stops giving focus to a view.
        .opacity(0.02)
        .focused($focusedHeroButton, equals: .pageBack)
        .accessibilityHidden(true)
    }

    /// Right from the last button pages forward; left from the first one pages back, unless the sidebar is there
    /// to take focus. A press that just moved focus between the buttons does not page.
    private func handleHeroMove(_ direction: MoveCommandDirection) {
        guard heroMode == .showcase, slides.count > 1,
              Date().timeIntervalSince(heroFocusChangedAt) > 0.15
        else { return }
        switch (direction, focusedHeroButton) {
        case (.right, .details):
            showSlide(at: currentIndex + 1)
        case (.left, .play) where settingsManager.interface.tabBarPlacement == .top:
            showSlide(at: currentIndex - 1)
        default:
            break
        }
    }

    private func showSlide(at index: Int) {
        guard !slides.isEmpty else { return }
        let wrapped = (index % slides.count + slides.count) % slides.count
        withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
            currentSlideID = slides[wrapped].id
        }
        autoAdvanceRestart += 1
    }

    private func setHeroMode(_ mode: HomeHeroMode) {
        guard heroMode != mode, mode == .browsing || !slides.isEmpty else { return }
        withAnimation(Motion.animation(Motion.showcase, reduceMotion: reduceMotion)) {
            heroMode = mode
        }
    }

    private struct AutoAdvanceKey: Equatable {
        let slide: MediaIdentity?
        let mode: HomeHeroMode
        let restart: Int
        let isActive: Bool
    }

    private var autoAdvanceKey: AutoAdvanceKey {
        AutoAdvanceKey(
            slide: currentSlide?.id,
            mode: heroMode,
            restart: autoAdvanceRestart,
            isActive: scenePhase == .active && !reduceMotion && !isVoiceOverEnabled,
        )
    }

    private func autoAdvance() async {
        guard autoAdvanceKey.isActive, heroMode == .showcase, slides.count > 1 else {
            autoAdvanceStartedAt = nil
            return
        }
        autoAdvanceStartedAt = Date()
        try? await Task.sleep(for: Self.autoAdvanceInterval)
        guard !Task.isCancelled else { return }
        showSlide(at: currentIndex + 1)
    }

    private func prefetchNextBackdrop() async {
        guard slides.count > 1 else { return }
        let next = slides[(currentIndex + 1) % slides.count].media
        guard let path = MediaHeroBackgroundView.artworkPath(
                  for: next,
                  spoilerProtection: settingsManager.interface.spoilerProtection,
              ),
              let services = registry.services(for: next.identity.server),
              let resource = try? await services.artwork.artwork(path: path, width: 3840, height: 2160)
        else { return }
        await ArtworkResourceView.preload(resource)
    }

    // MARK: - Rows

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.rows) { row in
                    HomeRowSectionView(
                        row: row,
                        showsLabels: settingsManager.interface.showsCardLabels,
                        onViewAll: coordinator.showHubDetail,
                        onSelectMedia: onSelectMedia,
                    )
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    RailsSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, LayoutMetrics.pageMargin)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.isLoading {
            GeometryReader { proxy in
                RailsSkeleton(showsLabels: settingsManager.interface.showsCardLabels)
                    .padding(.trailing, LayoutMetrics.pageMargin)
                    .frame(height: proxy.size.height * 0.60, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        } else {
            emptyMessage
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 16) {
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Focused card

    private var heroMedia: MediaItem? {
        viewModel.rows.lazy
            .flatMap { $0.items.compactMap(\.playableItem) }
            .first
    }

    private var visibleHeroMediaIDs: [String] {
        viewModel.rows.flatMap { $0.items.compactMap(\.playableItem).map(\.id) }
    }

    private var displayedHeroMedia: MediaItem? {
        if let focusedMedia = focusModel.focusedMedia,
           visibleHeroMediaIDs.contains(focusedMedia.id)
        {
            return focusedMedia
        }
        return heroMedia
    }

    private func updateInitialFocus() {
        guard let heroMedia else {
            focusModel.focusedMedia = nil
            return
        }
        guard focusModel.focusedMedia == nil || !visibleHeroMediaIDs.contains(focusModel.focusedMedia?.id ?? "") else {
            return
        }
        focusModel.focusedMedia = heroMedia
    }
}

/// Reads `cardFocusCount` apart from `HomeView`, which re-rendered the whole home and all of its cards on every focus
/// move along a row when it read it itself.
private struct CardFocusObserver: View {
    @Environment(MediaFocusModel.self) private var focusModel
    let onCardFocus: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: focusModel.cardFocusCount) {
                onCardFocus()
            }
    }
}
