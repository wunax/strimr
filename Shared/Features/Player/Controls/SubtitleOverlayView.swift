import AetherEngine
import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let currentTime: Double
    let maxCueDuration: Double
    let appearance: SubtitleAppearance
    let controlsVisible: Bool
    let videoSize: CGSize?

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                Color.clear
                    .overlay(alignment: .topLeading) {
                        ForEach(activeCues, id: \.id) { cue in
                            if case let .image(image) = cue.body {
                                imageView(image, in: geometry.size)
                            }
                        }
                    }
            }
            .ignoresSafeArea()

            GeometryReader { geometry in
                Color.clear
                    .overlay(alignment: appearance.verticalPosition.alignment) {
                        let lines = activeTextLines
                        if !lines.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    SubtitleTextView(text: line, appearance: appearance)
                                }
                            }
                            .frame(maxWidth: max(0, geometry.size.width - 48))
                            .padding(.top, appearance.verticalPosition == .top ? 48 : 0)
                            .padding(
                                .bottom,
                                appearance.verticalPosition == .bottom
                                    ? (controlsVisible ? 96 : 48)
                                    : 0,
                            )
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private var activeTextLines: [String] {
        activeCues.compactMap { cue in
            guard case let .text(text) = cue.body else { return nil }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private var activeCues: [SubtitleCue] {
        guard !cues.isEmpty else { return [] }

        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].startTime > currentTime {
                high = mid
            } else {
                low = mid + 1
            }
        }

        var result: [SubtitleCue] = []
        var index = low - 1
        while index >= 0, cues[index].startTime >= currentTime - maxCueDuration {
            if cues[index].endTime >= currentTime {
                result.append(cues[index])
            }
            index -= 1
        }
        return result.reversed()
    }

    private func imageView(_ image: SubtitleImage, in size: CGSize) -> some View {
        let frame = imageFrame(image, in: size)

        return Image(decorative: image.cgImage, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.high)
            .frame(
                width: frame.width,
                height: frame.height,
            )
            .offset(
                x: frame.minX,
                y: frame.minY,
            )
    }

    private func imageFrame(_ image: SubtitleImage, in overlaySize: CGSize) -> CGRect {
        guard let videoSize,
              videoSize.width > 0,
              videoSize.height > 0,
              overlaySize.width > 0,
              overlaySize.height > 0
        else {
            return CGRect(
                x: image.position.minX * overlaySize.width,
                y: image.position.minY * overlaySize.height,
                width: image.position.width * overlaySize.width,
                height: image.position.height * overlaySize.height,
            )
        }

        let videoScale = min(
            overlaySize.width / videoSize.width,
            overlaySize.height / videoSize.height,
        )
        let fittedVideoSize = CGSize(
            width: videoSize.width * videoScale,
            height: videoSize.height * videoScale,
        )
        let videoRect = CGRect(
            x: (overlaySize.width - fittedVideoSize.width) / 2,
            y: (overlaySize.height - fittedVideoSize.height) / 2,
            width: fittedVideoSize.width,
            height: fittedVideoSize.height,
        )

        let canvasSize = image.canvasSize.width > 0 && image.canvasSize.height > 0
            ? image.canvasSize
            : videoSize
        let canvasScale = videoRect.width / videoSize.width
        let fittedCanvasSize = CGSize(
            width: canvasSize.width * canvasScale,
            height: canvasSize.height * canvasScale,
        )
        let canvasRect = CGRect(
            x: videoRect.midX - fittedCanvasSize.width / 2,
            y: videoRect.midY - fittedCanvasSize.height / 2,
            width: fittedCanvasSize.width,
            height: fittedCanvasSize.height,
        )

        return CGRect(
            x: canvasRect.minX + image.position.minX * canvasRect.width,
            y: canvasRect.minY + image.position.minY * canvasRect.height,
            width: image.position.width * canvasRect.width,
            height: image.position.height * canvasRect.height,
        )
    }
}

struct SubtitleTextView: View {
    let text: String
    let appearance: SubtitleAppearance

    var body: some View {
        edgedText
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(
                .black.opacity(appearance.backgroundStrength.opacity),
                in: RoundedRectangle(cornerRadius: 6),
            )
    }

    @ViewBuilder
    private var edgedText: some View {
        switch appearance.edgeStyle {
        case .shadow:
            styledText(color: appearance.textColor.swiftUIColor)
                .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
        case .outline:
            ZStack {
                ForEach(Array(outlineOffsets.enumerated()), id: \.offset) { _, offset in
                    styledText(color: .black)
                        .offset(x: offset.width, y: offset.height)
                        .accessibilityHidden(true)
                }

                styledText(color: appearance.textColor.swiftUIColor)
            }
        case .none:
            styledText(color: appearance.textColor.swiftUIColor)
        }
    }

    private func styledText(color: Color) -> some View {
        Text(text)
            .font(
                .system(
                    size: CGFloat(appearance.fontSize),
                    weight: appearance.fontWeight.swiftUIWeight,
                ),
            )
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }

    private var outlineOffsets: [CGSize] {
        let width: CGFloat = 1.5
        return [
            CGSize(width: -width, height: -width),
            CGSize(width: 0, height: -width),
            CGSize(width: width, height: -width),
            CGSize(width: -width, height: 0),
            CGSize(width: width, height: 0),
            CGSize(width: -width, height: width),
            CGSize(width: 0, height: width),
            CGSize(width: width, height: width),
        ]
    }
}

struct SubtitleAppearancePreview: View {
    let appearance: SubtitleAppearance

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.8), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            SubtitleTextView(
                text: String(localized: "settings.playback.subtitles.preview.sample"),
                appearance: appearance,
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: appearance.verticalPosition.alignment,
            )
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("settings.playback.subtitles.preview.title")
    }
}

extension SubtitleTextColor {
    var localizedName: LocalizedStringKey {
        switch self {
        case .white:
            "settings.playback.subtitles.color.white"
        case .yellow:
            "settings.playback.subtitles.color.yellow"
        case .cyan:
            "settings.playback.subtitles.color.cyan"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .white:
            .white
        case .yellow:
            .yellow
        case .cyan:
            .cyan
        }
    }
}

extension SubtitleFontWeight {
    var localizedName: LocalizedStringKey {
        switch self {
        case .regular:
            "settings.playback.subtitles.weight.regular"
        case .medium:
            "settings.playback.subtitles.weight.medium"
        case .semibold:
            "settings.playback.subtitles.weight.semibold"
        case .bold:
            "settings.playback.subtitles.weight.bold"
        }
    }

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular:
            .regular
        case .medium:
            .medium
        case .semibold:
            .semibold
        case .bold:
            .bold
        }
    }
}

extension SubtitleBackgroundStrength {
    var localizedName: LocalizedStringKey {
        switch self {
        case .none:
            "settings.playback.subtitles.background.none"
        case .subtle:
            "settings.playback.subtitles.background.subtle"
        case .standard:
            "settings.playback.subtitles.background.standard"
        case .strong:
            "settings.playback.subtitles.background.strong"
        }
    }

    var opacity: Double {
        switch self {
        case .none:
            0
        case .subtle:
            0.2
        case .standard:
            0.35
        case .strong:
            0.65
        }
    }
}

extension SubtitleEdgeStyle {
    var localizedName: LocalizedStringKey {
        switch self {
        case .shadow:
            "settings.playback.subtitles.edge.shadow"
        case .outline:
            "settings.playback.subtitles.edge.outline"
        case .none:
            "settings.playback.subtitles.edge.none"
        }
    }
}

extension SubtitleVerticalPosition {
    var localizedName: LocalizedStringKey {
        switch self {
        case .bottom:
            "settings.playback.subtitles.position.bottom"
        case .middle:
            "settings.playback.subtitles.position.middle"
        case .top:
            "settings.playback.subtitles.position.top"
        }
    }

    var alignment: Alignment {
        switch self {
        case .bottom:
            .bottom
        case .middle:
            .center
        case .top:
            .top
        }
    }
}
