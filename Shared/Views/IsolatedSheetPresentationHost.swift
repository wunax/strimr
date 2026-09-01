import Observation
import SwiftUI

@MainActor
@Observable
final class IsolatedSheetPresentation<Item: Identifiable> {
    var item: Item?

    // Work around https://github.com/swiftlang/swift/issues/87462.
    // Remove this workaround when Swift 6.4 is adopted, which should include the fix.
    @inline(never)
    deinit {}
}

struct IsolatedSheetPresentationHost<Item: Identifiable, SheetContent: View>: View, Equatable {
    let presentation: IsolatedSheetPresentation<Item>
    let refreshID: AnyHashable
    let onDismiss: () -> Void
    let sheetContent: (Item) -> SheetContent

    init(
        presentation: IsolatedSheetPresentation<Item>,
        refreshID: AnyHashable,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder sheetContent: @escaping (Item) -> SheetContent,
    ) {
        self.presentation = presentation
        self.refreshID = refreshID
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.presentation === rhs.presentation && lhs.refreshID == rhs.refreshID
    }

    var body: some View {
        @Bindable var presentation = presentation

        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $presentation.item, onDismiss: onDismiss) { item in
                sheetContent(item)
            }
    }
}
