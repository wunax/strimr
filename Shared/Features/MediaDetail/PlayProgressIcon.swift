import SwiftUI

/// Play glyph of the white play button, ringed by the resume progress when there is some.
struct PlayProgressIcon: View {
    let progress: Double?
    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(Color.black.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.black,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: "play.fill")
                .font(glyphFont)
        }
        .frame(width: size, height: size)
    }

    private var size: CGFloat {
        #if os(tvOS)
            36
        #else
            30
        #endif
    }

    private var glyphFont: Font {
        #if os(tvOS)
            .system(size: 18, weight: .semibold)
        #else
            .title3.weight(.semibold)
        #endif
    }
}
