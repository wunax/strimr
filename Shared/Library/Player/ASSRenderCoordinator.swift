import AetherEngine
import Combine
import Foundation
import QuartzCore
import SwiftAssRenderer

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

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
    private var frameTicker: ASSFrameTicker?
    private var lastOffset = 0.0
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

        // Fallback for when no display link ticks (no screen on macOS).
        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyTimeOffset()
            }
            .store(in: &cancellables)

        installRenderer(fonts: engine.fontAttachments)
        frameTicker = ASSFrameTicker { [weak self] in
            guard let self else { return false }
            applyTimeOffset()
            return true
        }
    }

    /// Positive shows subtitles later. Pushed right away so a paused picture follows the change.
    func setSubtitleDelay(seconds: Double) {
        guard subtitleDelaySeconds != seconds else { return }
        subtitleDelaySeconds = seconds
        guard builder != nil else { return }
        applyTimeOffset()
    }

    func deactivate() {
        frameTicker?.invalidate()
        frameTicker = nil
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
        let sourceTime = ASSPresentationClock.sourceSeconds(
            presented: engine.presentedSourceTime,
            published: engine.clock.sourceTime,
            followsPicture: engine.clock.sourceTimeFollowsPicture,
        )
        let offset = sourceTime - subtitleDelaySeconds
        if offset != lastOffset {
            lastOffset = offset
            renderer?.setTimeOffset(offset)
        }
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

/// Picks the time libass renders at: the presenting clock read now, or the published clock, which
/// only ticks at 4 to 10 Hz and would let a line outlive a scene cut by several frames.
enum ASSPresentationClock {
    /// Further apart than this, the presenting clock is mid-seek or not armed yet rather than ahead of a coarse tick.
    static let maxDriftSeconds = 1.0

    static func sourceSeconds(presented: Double?, published: Double, followsPicture: Bool) -> Double {
        guard followsPicture, let presented, abs(presented - published) <= maxDriftSeconds else {
            return published
        }
        return presented
    }
}

/// Ticks on display refresh, capped near film frame rates since a subtitle frame never needs more.
@MainActor
private final class ASSFrameTicker: NSObject {
    private var displayLink: CADisplayLink?
    /// Returns false once its owner is gone, which stops the link.
    private let onTick: () -> Bool

    init?(onTick: @escaping () -> Bool) {
        self.onTick = onTick
        super.init()
        #if canImport(UIKit)
            let link = CADisplayLink(target: self, selector: #selector(tick))
        #elseif canImport(AppKit)
            guard let link = NSScreen.main?.displayLink(target: self, selector: #selector(tick)) else { return nil }
        #endif
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        if !onTick() {
            invalidate()
        }
    }
}
