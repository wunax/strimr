import SwiftUI

struct PlayerBadge: View {
    var title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .playerBadgeStyle()
    }
}

extension View {
    /// Glass capsule of a small label shown over playing video, such as the video format or the sleep timer.
    func playerBadgeStyle() -> some View {
        font(.badge)
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .videoOverlayGlass()
    }
}
