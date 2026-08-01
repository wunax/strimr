import AetherEngine
import Combine
import SwiftAssRenderer
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let currentTime: Double
    let maxCueDuration: Double
    let appearance: SubtitleAppearance
    let bottomPadding: CGFloat
    let videoSize: CGSize?
    let assRenderer: AssSubtitlesRenderer?
    let assReloadSignal: PassthroughSubject<Void, Never>
    let activeSubtitleCodec: String?

    var body: some View {
        if let assRenderer {
            ASSRenderedSubtitles(
                renderer: assRenderer,
                reloadSignal: assReloadSignal,
                currentOffset: currentTime,
            )
            .allowsHitTesting(false)
        } else {
            cueOverlay
        }
    }

    private var cueOverlay: some View {
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
                                    ? bottomPadding
                                    : 0,
                            )
                            .animation(.easeInOut(duration: 0.2), value: bottomPadding)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private var activeTextLines: [String] {
        activeCues.compactMap { cue in
            guard case let .text(text) = cue.body else { return nil }
            let displayText = isASSTrackActive ? strippedASSText(text) : text
            let cleaned = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private var isASSTrackActive: Bool {
        activeSubtitleCodec == "ass" || activeSubtitleCodec == "ssa"
    }

    private func strippedASSText(_ rawText: String) -> String {
        var lines: [String] = []
        for line in rawText.split(separator: "\n") {
            let fields = line.split(separator: ",", maxSplits: 8, omittingEmptySubsequences: false)
            guard fields.count == 9, Int(fields[0]) != nil else {
                lines.append(String(line))
                continue
            }

            var text = String(fields[8])
            text = text.replacingOccurrences(of: "\\N", with: "\n")
            text = text.replacingOccurrences(of: "\\n", with: "\n")
            text = text.replacingOccurrences(of: "\\h", with: " ")
            text = text.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }
        return lines.joined(separator: "\n")
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

private struct ASSRenderedSubtitles: PlatformViewRepresentable {
    let renderer: AssSubtitlesRenderer
    let reloadSignal: PassthroughSubject<Void, Never>
    let currentOffset: Double

    #if canImport(UIKit)
        func makeUIView(context _: Context) -> ASSFrameHostView {
            ASSFrameHostView(renderer: renderer, reloadSignal: reloadSignal)
        }

        func updateUIView(_ view: ASSFrameHostView, context _: Context) {
            view.currentOffset = currentOffset
        }
    #elseif canImport(AppKit)
        func makeNSView(context _: Context) -> ASSFrameHostView {
            ASSFrameHostView(renderer: renderer, reloadSignal: reloadSignal)
        }

        func updateNSView(_ view: ASSFrameHostView, context _: Context) {
            view.currentOffset = currentOffset
        }
    #endif
}

private final class ASSFrameHostView: PlatformView {
    var currentOffset = 0.0

    private let renderer: AssSubtitlesRenderer
    private let imageView = PlatformImageView()
    private var lastRenderBounds = CGRect.zero
    private var cancellables: Set<AnyCancellable> = []
    private var suppressNilDeadline = Date.distantPast
    private var hideWorkItem: DispatchWorkItem?

    private static let reloadSuppressWindow: TimeInterval = 0.5

    init(renderer: AssSubtitlesRenderer, reloadSignal: PassthroughSubject<Void, Never>) {
        self.renderer = renderer
        super.init(frame: .zero)

        #if canImport(UIKit)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        #elseif canImport(AppKit)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        #endif

        addSubview(imageView)
        reloadSignal
            .sink { [weak self] in
                self?.suppressNilDeadline = Date().addingTimeInterval(Self.reloadSuppressWindow)
            }
            .store(in: &cancellables)
        renderer.framesPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] image in
                self?.handleFrameChanged(image)
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            layoutRenderer()
        }
    #elseif canImport(AppKit)
        override func layout() {
            super.layout()
            layoutRenderer()
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    #endif

    private func layoutRenderer() {
        guard !bounds.isEmpty else { return }

        if !lastRenderBounds.isEmpty, imageView.image != nil, lastRenderBounds != bounds {
            let ratioX = bounds.width / lastRenderBounds.width
            let ratioY = bounds.height / lastRenderBounds.height
            let frame = imageView.frame
            imageView.frame = CGRect(
                x: frame.origin.x * ratioX,
                y: frame.origin.y * ratioY,
                width: frame.width * ratioX,
                height: frame.height * ratioY,
            ).integral
        }
        renderer.setCanvasSize(bounds.size, scale: displayScale)
    }

    private var displayScale: CGFloat {
        #if canImport(UIKit)
            traitCollection.displayScale
        #elseif canImport(AppKit)
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    private func handleFrameChanged(_ image: ProcessedImage?) {
        if let image {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            suppressNilDeadline = .distantPast
            lastRenderBounds = bounds
            imageView.frame = imageFrame(image.imageRect)
            #if canImport(UIKit)
                imageView.image = PlatformImage(cgImage: image.image)
            #elseif canImport(AppKit)
                imageView.image = PlatformImage(cgImage: image.image, size: image.imageRect.size)
            #endif
            imageView.isHidden = false
            return
        }

        let remaining = suppressNilDeadline.timeIntervalSinceNow
        guard remaining > 0 else {
            hideNow()
            return
        }
        guard hideWorkItem == nil else { return }
        scheduleSafetyHide(after: remaining)
    }

    private func imageFrame(_ rect: CGRect) -> CGRect {
        #if canImport(UIKit)
            rect
        #elseif canImport(AppKit)
            CGRect(
                x: rect.minX,
                y: bounds.height - rect.maxY,
                width: rect.width,
                height: rect.height,
            )
        #endif
    }

    private func scheduleSafetyHide(after delay: TimeInterval) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hideWorkItem = nil
            let remaining = suppressNilDeadline.timeIntervalSinceNow
            if remaining > 0 {
                scheduleSafetyHide(after: remaining)
            } else if !renderer.dialogues(at: currentOffset).isEmpty {
                suppressNilDeadline = .distantPast
                scheduleEndWatch()
            } else {
                hideNow()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleEndWatch() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hideWorkItem = nil
            if renderer.dialogues(at: currentOffset).isEmpty {
                hideNow()
            } else {
                scheduleEndWatch()
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func hideNow() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        imageView.isHidden = true
        imageView.image = nil
        suppressNilDeadline = .distantPast
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
