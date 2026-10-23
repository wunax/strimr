import SwiftUI

/// Toggle of a list filter, such as the kinds of a search, the statuses of Seerr requests or the season of a detail
/// page.
struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(.chip(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
