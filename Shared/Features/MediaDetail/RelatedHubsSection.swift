import Observation
import SwiftUI

struct RelatedHubsSection: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
        @EnvironmentObject private var coordinator: MainCoordinator
    #endif
    @Bindable var viewModel: MediaDetailViewModel
    #if !os(tvOS)
        @State private var selectedHub: Hub?
    #endif
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                relatedContent
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .textCase(nil)
        #if !os(tvOS)
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
        #endif
    }

    @ViewBuilder
    private var relatedContent: some View {
        if let errorMessage = viewModel.relatedHubsErrorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        } else if viewModel.isLoadingRelatedHubs, viewModel.relatedHubs.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("media.detail.loadingRelated")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.relatedHubs.isEmpty {
            Text("media.detail.noRelated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.relatedHubs) { hub in
                    MediaHubSection(
                        title: hub.title,
                        onViewAll: headerViewAllAction(for: hub),
                    ) {
                        MediaCarousel(
                            layout: .portrait,
                            items: hub.items,
                            showsLabels: true,
                            onViewAll: carouselViewAllAction(for: hub),
                            onSelectMedia: onSelectMedia,
                        )
                    }
                }
            }
        }
    }

    private func headerViewAllAction(for hub: Hub) -> (() -> Void)? {
        #if !os(tvOS)
            guard hub.canOpenDetail else { return nil }
            return { selectedHub = hub }
        #else
            return nil
        #endif
    }

    private func carouselViewAllAction(for hub: Hub) -> (() -> Void)? {
        guard hub.canShowViewAll else { return nil }
        #if os(tvOS)
            return { coordinator.showHubDetail(hub) }
        #else
            return nil
        #endif
    }
}
