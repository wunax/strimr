import SwiftUI

#if os(macOS)
private struct MouseDragScrollingModifier: ViewModifier {
    @State private var position = ScrollPosition(point: .zero)
    @State private var currentOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x + geometry.contentInsets.leading
            } action: { _, offset in
                currentOffset = offset
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if dragStartOffset == nil {
                            dragStartOffset = currentOffset
                        }

                        let offset = (dragStartOffset ?? currentOffset) - value.translation.width
                        position.scrollTo(x: max(0, offset))
                    }
                    .onEnded { _ in
                        dragStartOffset = nil
                    },
            )
    }
}
#endif

extension View {
    @ViewBuilder
    func mouseDragScrolling() -> some View {
        #if os(macOS)
            modifier(MouseDragScrollingModifier())
        #else
            self
        #endif
    }
}
