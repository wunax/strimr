import SwiftUI

/// Avatar of a local profile: its initials on a gradient.
struct ProfileInitialsAvatar: View {
    let initials: String
    var tint: Color = .brandPrimary

    var body: some View {
        LinearGradient(
            colors: [tint, tint.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay {
            GeometryReader { geometry in
                Text(initials)
                    .font(.system(size: geometry.size.width * 0.36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
