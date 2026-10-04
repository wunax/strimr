import SwiftUI

/// Fits as many columns of at least `targetWidth` as possible, then widens cards so each row fills the width.
struct PosterGridLayout: Equatable {
    let columnCount: Int
    let cardWidth: CGFloat

    init(availableWidth: CGFloat, targetWidth: CGFloat, spacing: CGFloat) {
        guard availableWidth > 0 else {
            columnCount = 1
            cardWidth = targetWidth
            return
        }
        columnCount = max(1, Int((availableWidth + spacing) / (targetWidth + spacing)))
        cardWidth = ((availableWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)).rounded(.down)
    }
}

struct PosterGrid<Content: View>: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var availableWidth: CGFloat = 0

    let spacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        let layout = PosterGridLayout(
            availableWidth: availableWidth,
            targetWidth: settingsManager.interface.posterSize.gridCardWidth,
            spacing: spacing,
        )
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(layout.cardWidth), spacing: spacing, alignment: .top),
                count: layout.columnCount,
            ),
            alignment: .leading,
            spacing: rowSpacing,
        ) {
            content(layout.cardWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}
