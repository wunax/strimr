import AetherEngine
import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let currentTime: Double
    let maxCueDuration: Double
    let subtitleFontSize: Int
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
                    .overlay(alignment: .bottom) {
                        let lines = activeTextLines
                        if !lines.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: pointSize, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                        .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 5)
                                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .frame(maxWidth: max(0, geometry.size.width - 48))
                            .padding(.bottom, controlsVisible ? 96 : 48)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private var pointSize: CGFloat {
        CGFloat(subtitleFontSize)
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
