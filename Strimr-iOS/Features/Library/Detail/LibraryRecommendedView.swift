import SwiftUI

struct LibraryRecommendedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let landscapeHubIdentifiers: [String] = [
        "inprogress",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.hubs) { hub in
                    if hub.hasItems {
                        MediaHubSection(title: hub.title) {
                            carousel(for: hub)
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("library.recommended.loading")
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
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            MediaCarousel(
                layout: .landscape,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }
}
