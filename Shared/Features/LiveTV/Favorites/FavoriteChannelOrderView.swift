import SwiftUI

struct FavoriteChannelOrderView: View {
    @Bindable var store: LiveTVStore
    @Environment(\.dismiss) private var dismiss
    @State private var favorites: [LiveTVChannel] = []

    var body: some View {
        TaskModalNavigationView {
            List {
                if favorites.isEmpty {
                    Text("livetv.empty.favorites")
                }
                ForEach(Array(favorites.enumerated()), id: \.element.id) { index, channel in
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(channel.displayTitle)
                        Spacer()
                        Button("livetv.favorites.moveUp", systemImage: "chevron.up") { move(index, by: -1) }
                            .labelStyle(.iconOnly)
                            .disabled(index == 0)
                        Button("livetv.favorites.moveDown", systemImage: "chevron.down") { move(index, by: 1) }
                            .labelStyle(.iconOnly)
                            .disabled(index + 1 == favorites.count)
                    }
                }
            }
            .taskModalTitle("livetv.favorites.manage")
            .taskModalActions { Button("common.done") { dismiss() } }
            .onAppear { favorites = store.channels.filter(\.isFavorite) }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard favorites.indices.contains(destination) else { return }
        favorites.swapAt(index, destination)
        let reordered = favorites
        Task {
            do {
                try await store.reorderFavorites(reordered)
            } catch {
                LiveTVErrorReporting.capture(error)
            }
        }
    }
}
