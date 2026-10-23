import SwiftUI

extension View {
    /// Navigation chrome of a tab's root screen: on iOS, an inline title and the user menu.
    @ViewBuilder
    func tabRootChrome() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
                .userMenuToolbar()
        #else
            self
        #endif
    }
}
