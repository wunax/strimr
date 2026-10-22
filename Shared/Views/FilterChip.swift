import SwiftUI

/// Toggle of a list filter, such as the kinds of a search or the statuses of Seerr requests. The brand color only
/// marks the selected state.
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
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.brandPrimary.opacity(0.18) : .surfaceSubtle),
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.brandPrimary : .strokeSubtle, lineWidth: 1)
            }
            // Hierarchical rather than `textPrimary`: the focused tvOS button turns white and it inverts.
            .foregroundStyle(isSelected ? Color.brandPrimary : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
