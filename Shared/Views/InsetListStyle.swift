import SwiftUI

extension View {
    /// Inset list of settings and sheets: grouped on iOS, plain inset on macOS.
    func insetListStyle() -> some View {
        #if os(macOS)
            listStyle(.inset)
        #else
            listStyle(.insetGrouped)
        #endif
    }
}
