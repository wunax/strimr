import SwiftUI

@MainActor
struct FavoritesView: View {
    @State private var viewModel: FavoritesViewModel
    @State private var selectedCategory: FavoriteCategory?

    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        services: MediaServices,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: FavoritesViewModel(services: services))
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(FavoriteCategory.allCases) { category in
                    let items = viewModel.items(for: category)
                    if !items.isEmpty {
                        MediaHubSection(
                            title: category.title,
                            onViewAll: { selectedCategory = category },
                        ) {
                            MediaCarousel(
                                layout: category.layout,
                                items: Array(items.prefix(12)),
                                showsLabels: true,
                                onViewAll: carouselViewAllAction(for: category),
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }
                }

                if viewModel.isLoading, viewModel.itemsByCategory.isEmpty {
                    ProgressView("favorites.loading")
                        .frame(maxWidth: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.isLoading,
                          !FavoriteCategory.allCases.contains(where: { !viewModel.items(for: $0).isEmpty })
                {
                    VStack(spacing: 8) {
                        Image(systemName: "star")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("favorites.empty.title")
                            .font(.headline)
                        Text("favorites.empty.description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.favorites")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .navigationDestination(item: $selectedCategory) { category in
            FavoriteCategoryView(
                category: category,
                items: viewModel.items(for: category),
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private func carouselViewAllAction(for category: FavoriteCategory) -> (() -> Void)? {
        #if os(tvOS)
            return { selectedCategory = category }
        #else
            return nil
        #endif
    }
}

@MainActor
private struct FavoriteCategoryView: View {
    let category: FavoriteCategory
    let items: [MediaDisplayItem]
    let onSelectMedia: (MediaDisplayItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(items, id: \.id) { item in
                    if category == .episodes {
                        LandscapeMediaCard(media: item, showsLabels: true) {
                            onSelectMedia(item)
                        }
                    } else {
                        PortraitMediaCard(media: item, showsLabels: true) {
                            onSelectMedia(item)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle(category.title)
    }
}
