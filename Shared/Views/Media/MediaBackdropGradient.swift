import SwiftUI

struct MediaBackdropGradient: View {
    let colors: [Color]

    var body: some View {
        let gradientColors = colors.count == 4 ? colors : [
            Color.background.opacity(0.85),
            Color.background.opacity(0.7),
            Color.background.opacity(0.55),
            Color.background.opacity(0.4),
        ]

        GeometryReader { geo in
            ZStack {
                Color(.background)
                    .ignoresSafeArea()

                // Top Left
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[0], .clear]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75,
                )

                // Top Right
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[1], .clear]),
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75,
                )

                // Bottom Right
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[2], .clear]),
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75,
                )

                // Bottom Left
                RadialGradient(
                    gradient: Gradient(colors: [gradientColors[3], .clear]),
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.75,
                )
            }
        }
    }
}

extension MediaBackdropGradient {
    static func colors(for media: MediaDisplayItem) -> [Color] {
        guard let blur = media.ultraBlurColors else { return [] }
        return [
            Color(hex: blur.topLeft),
            Color(hex: blur.topRight),
            Color(hex: blur.bottomRight),
            Color(hex: blur.bottomLeft),
        ]
    }
}
