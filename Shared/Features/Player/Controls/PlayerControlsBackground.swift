import SwiftUI

/// Darkens the top and bottom of the video behind the player controls so they stay readable.
struct PlayerControlsBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.topHeight)

            Spacer()

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.bottomHeight)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private static var topHeight: CGFloat {
        #if os(tvOS)
            200
        #elseif os(macOS)
            160
        #else
            180
        #endif
    }

    private static var bottomHeight: CGFloat {
        #if os(tvOS)
            280
        #elseif os(macOS)
            240
        #else
            260
        #endif
    }
}
