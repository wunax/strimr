import SwiftUI

struct HeroContentTransitionView<Item: Identifiable, Content: View>: View {
    let item: Item
    @ViewBuilder let content: (Item) -> Content

    @State private var displayedItem: Item?
    @State private var isVisible = true
    @State private var verticalOffset: CGFloat = 0

    private let fadeOutDuration: TimeInterval = 0.15
    private let fadeInDuration: TimeInterval = 0.25

    var body: some View {
        // Render the latest item when ids match so same-id metadata refreshes aren't stale.
        content(displayedItem.map { $0.id == item.id ? item : $0 } ?? item)
            .opacity(isVisible ? 1 : 0)
            .offset(y: verticalOffset)
            .task(id: item.id) {
                await transition()
            }
    }

    /// Sequential fade out then in so the outgoing and incoming text never overlap;
    /// rapid focus changes cancel the task and keep the text hidden until focus settles.
    private func transition() async {
        guard let current = displayedItem, current.id != item.id else {
            displayedItem = item
            withAnimation(.easeOut(duration: fadeInDuration)) {
                isVisible = true
            }
            return
        }

        withAnimation(.easeIn(duration: fadeOutDuration)) {
            isVisible = false
        }
        try? await Task.sleep(for: .seconds(fadeOutDuration))
        guard !Task.isCancelled else { return }

        displayedItem = item
        verticalOffset = 12
        withAnimation(.easeOut(duration: fadeInDuration)) {
            isVisible = true
            verticalOffset = 0
        }
    }
}
