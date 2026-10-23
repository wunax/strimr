import SwiftUI

struct WatchStatusBadge: View {
    let media: MediaDisplayItem

    var body: some View {
        if let remaining = media.remainingUnwatchedLeaves {
            Text("\(remaining)")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.badgeBackground, in: Capsule(style: .continuous))
                .badgeStyle()
        } else if media.isFullyWatched {
            Image(systemName: "checkmark")
                .padding(6)
                .background(.badgeBackground, in: Circle())
                .badgeStyle()
        }
    }
}

private extension View {
    func badgeStyle() -> some View {
        font(.badge)
            .foregroundStyle(.textPrimary)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(8)
    }
}
