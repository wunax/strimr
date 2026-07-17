import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: HomeViewModel
    @State private var selectedHub: Hub?
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(
                        title: hub.title,
                        onViewAll: hub.canOpenDetail ? { selectedHub = hub } : nil,
                    ) {
                        MediaCarousel(
                            layout: .landscape,
                            items: hub.items,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }

                if !viewModel.recentlyAdded.isEmpty {
                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            MediaHubSection(
                                title: hub.title,
                                onViewAll: hub.canOpenDetail ? { selectedHub = hub } : nil,
                            ) {
                                MediaCarousel(
                                    layout: .portrait,
                                    items: hub.items,
                                    showsLabels: true,
                                    onSelectMedia: onSelectMedia,
                                )
                            }
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("home.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.home")
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .refreshable {
            await viewModel.reload()
        }
        .sheet(item: $selectedHub) { hub in
            NavigationStack {
                HubDetailView(
                    viewModel: HubDetailViewModel(hub: hub, context: plexApiContext),
                    onSelectMedia: { media in
                        selectedHub = nil
                        onSelectMedia(media)
                    },
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("hub.close") {
                            selectedHub = nil
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }
}
