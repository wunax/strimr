import AetherEngine
import Combine
import Foundation
import SwiftAssRenderer

@MainActor
final class ASSRenderCoordinator {
    private(set) var renderer: AssSubtitlesRenderer?

    var onRendererChanged: ((AssSubtitlesRenderer?) -> Void)?

    private let engine: AetherEngine
    private var builder: ASSScriptBuilder?
    private var cancellables: Set<AnyCancellable> = []
    private var lastReloadAt = Date.distantPast
    private var pendingEvents = false
    private var earliestPendingStart = Double.infinity
    private var lastOffset = 0.0
    private var lastSourceTime = 0.0
    private var subtitleDelaySeconds = 0.0

    private let reloadInterval: TimeInterval = 5
    private let imminentLeadSeconds = 10.0
    private let minImminentSpacing: TimeInterval = 0.25

    init(engine: AetherEngine) {
        self.engine = engine
    }

    func activate(header: String?) {
        deactivate()
        guard let header, !header.isEmpty else { return }

        builder = ASSScriptBuilder(header: header)

        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                self?.consume(cues: cues)
            }
            .store(in: &cancellables)

        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                lastSourceTime = time
                applyTimeOffset()
            }
            .store(in: &cancellables)

        installRenderer(fonts: engine.fontAttachments)
    }

    /// Positive shows subtitles later. Pushed right away so a paused picture follows the change.
    func setSubtitleDelay(seconds: Double) {
        guard subtitleDelaySeconds != seconds else { return }
        subtitleDelaySeconds = seconds
        guard builder != nil else { return }
        applyTimeOffset()
    }

    func deactivate() {
        cancellables.removeAll()
        renderer?.freeTrack()
        renderer = nil
        builder = nil
        pendingEvents = false
        earliestPendingStart = .infinity
        lastReloadAt = .distantPast
        onRendererChanged?(nil)
    }

    private func applyTimeOffset() {
        lastOffset = lastSourceTime - subtitleDelaySeconds
        renderer?.setTimeOffset(lastOffset)
        flushPendingEventsIfDue()
    }

    private func installRenderer(fonts: [FontAttachment]) {
        // With CoreText, `fontsPath` is never scanned: attached fonts only reach libass from memory.
        let fontConfig = FontConfig(
            fontsPath: FileManager.default.temporaryDirectory,
            fontProvider: .coreText,
            embeddedFonts: fonts.map { EmbeddedFont(name: $0.filename, data: $0.data) },
        )
        let renderer = AssSubtitlesRenderer(fontConfig: fontConfig)
        renderer.setTimeOffset(lastOffset)
        self.renderer = renderer
        onRendererChanged?(renderer)
        flushPendingEventsIfDue()
    }

    private func consume(cues: [SubtitleCue]) {
        guard let builder else { return }

        var addedEvent = false
        for cue in cues {
            guard case let .text(rawText) = cue.body else { continue }
            if builder.add(rawEventText: rawText, start: cue.startTime, end: cue.endTime) {
                addedEvent = true
                earliestPendingStart = min(earliestPendingStart, cue.startTime)
            }
        }

        if addedEvent {
            pendingEvents = true
        }
        flushPendingEventsIfDue()
    }

    private func flushPendingEventsIfDue() {
        guard pendingEvents, let builder, let renderer else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastReloadAt)
        let isImminent = earliestPendingStart <= lastOffset + imminentLeadSeconds
        let isDue = isImminent ? elapsed >= minImminentSpacing : elapsed >= reloadInterval
        guard isDue else { return }

        lastReloadAt = now
        pendingEvents = false
        earliestPendingStart = .infinity
        renderer.reloadTrack(content: builder.script())
    }
}
