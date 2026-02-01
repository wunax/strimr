import SwiftUI

struct WatchStatusBadge: View {
    let media: MediaDisplayItem

    var body: some View {
        Group {
            if let remaining = media.remainingUnwatchedLeaves {
                badge {
                    Text("\(remaining)")
                }
            } else if media.isFullyWatched {
                badge {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func badge(@ViewBuilder content: () -> some View) -> some View {
        content()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(8)
    }
}
