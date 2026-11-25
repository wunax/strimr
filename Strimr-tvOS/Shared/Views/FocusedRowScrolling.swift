import SwiftUI

extension View {
    /// Scrolls the row holding focus to the top of a vertical `ScrollView`, so its title stays in view: the focus
    /// engine alone only scrolls the focused card into view and leaves the title above it cut off. Each row needs
    /// `.id(rowID)` and `.focused($focusedRow, equals: rowID)`.
    func scrollsFocusedRowToTop(_ focusedRow: (some Hashable)?) -> some View {
        modifier(FocusedRowScrolling(focusedRow: focusedRow))
    }
}

private struct FocusedRowScrolling<ID: Hashable>: ViewModifier {
    let focusedRow: ID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition(idType: ID.self)
    @State private var viewportHeight: CGFloat = 0
    @State private var latestFocusedRow: ID?

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            // Room below the last row, which would otherwise stop where the content ends instead of at the top.
            .contentMargins(.bottom, viewportHeight, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            .onChange(of: focusedRow) { _, row in
                latestFocusedRow = row
                guard let row else { return }
                // The focus engine scrolls the card into view right after focus moves; waiting a turn lands after it.
                DispatchQueue.main.async {
                    // Holding a direction moves focus across several rows: only the row still focused scrolls.
                    guard latestFocusedRow == row else { return }
                    withAnimation(Motion.animation(Motion.rowScroll, reduceMotion: reduceMotion)) {
                        position.scrollTo(id: row, anchor: .top)
                    }
                }
            }
    }
}
