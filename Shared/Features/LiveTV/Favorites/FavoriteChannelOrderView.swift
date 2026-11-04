import SwiftUI

struct FavoriteChannelOrderView: View {
    @Bindable var store: LiveTVStore
    @Environment(\.dismiss) private var dismiss
    @State private var favorites: [LiveTVChannel] = []
    @State private var saveTask: Task<Void, Never>?

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
        save(favorites)
    }

    /// Sends only the last order of a burst of moves, and never while an earlier request can still finish after it.
    private func save(_ reordered: [LiveTVChannel]) {
        let previous = saveTask
        previous?.cancel()
        saveTask = Task {
            await previous?.value
            do {
                try await Task.sleep(for: .milliseconds(400))
                try await store.reorderFavorites(reordered)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                LiveTVErrorReporting.capture(error)
                favorites = store.channels.filter(\.isFavorite)
            }
        }
    }
}
