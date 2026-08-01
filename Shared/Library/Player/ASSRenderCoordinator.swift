import AetherEngine
import Combine
import Foundation
import SwiftAssRenderer

@MainActor
final class ASSRenderCoordinator {
    private(set) var renderer: AssSubtitlesRenderer?
    let reloadSignal = PassthroughSubject<Void, Never>()

    var onRendererChanged: ((AssSubtitlesRenderer?) -> Void)?

    private let engine: AetherEngine
    private var builder: ASSScriptBuilder?
    private var cancellables: Set<AnyCancellable> = []
    private var lastReloadAt = Date.distantPast
    private var pendingEvents = false
    private var earliestPendingStart = Double.infinity
    private var lastOffset = 0.0
    private var activationGeneration = 0

    private let reloadInterval: TimeInterval = 5
    private let imminentLeadSeconds = 10.0
    private let minImminentSpacing: TimeInterval = 0.25

    init(engine: AetherEngine) {
        self.engine = engine
    }

    func activate(header: String?, mediaIdentifier: String) {
        deactivate()
        guard let header, !header.isEmpty else { return }

        activationGeneration += 1
        let generation = activationGeneration
        let fontsDirectory = Self.fontsDirectory(mediaIdentifier: mediaIdentifier)
        let fonts = engine.fontAttachments
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
                lastOffset = time
                renderer?.setTimeOffset(time)
                flushPendingEventsIfDue()
            }
            .store(in: &cancellables)

        let fontsReady = FileManager.default.fileExists(atPath: fontsDirectory.path)
            && Self.allFontsPresent(fonts, in: fontsDirectory)
        if fontsReady {
            installRenderer(fontsDirectory: fontsDirectory)
        } else {
            Task { [weak self] in
                let preparationError = await Task.detached(priority: .userInitiated) {
                    Self.prepareFontDirectory(fonts, at: fontsDirectory)
                }.value
                guard let self, activationGeneration == generation else { return }
                if let preparationError {
                    ErrorReporter.capture(preparationError)
                }
                installRenderer(fontsDirectory: fontsDirectory)
            }
        }
    }

    func deactivate() {
        activationGeneration += 1
        cancellables.removeAll()
        renderer?.freeTrack()
        renderer = nil
        builder = nil
        pendingEvents = false
        earliestPendingStart = .infinity
        lastReloadAt = .distantPast
        onRendererChanged?(nil)
    }

    private func installRenderer(fontsDirectory: URL) {
        let fontConfig = FontConfig(fontsPath: fontsDirectory, fontProvider: .coreText)
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
        reloadSignal.send()
        renderer.reloadTrack(content: builder.script())
    }

    private static func fontsDirectory(mediaIdentifier: String) -> URL {
        let safeIdentifier = (mediaIdentifier as NSString).lastPathComponent
        let directoryName = safeIdentifier.isEmpty || safeIdentifier == ".." ? "media" : safeIdentifier
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ass-fonts", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private nonisolated static func allFontsPresent(_ fonts: [FontAttachment], in directory: URL) -> Bool {
        fonts.allSatisfy { font in
            let safeName = (font.filename as NSString).lastPathComponent
            guard !safeName.isEmpty else { return true }
            return FileManager.default.fileExists(atPath: directory.appendingPathComponent(safeName).path)
        }
    }

    private nonisolated static func prepareFontDirectory(
        _ fonts: [FontAttachment],
        at directory: URL,
    ) -> ASSFontCacheError? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .createDirectoryFailed
        }

        for font in fonts {
            let safeName = (font.filename as NSString).lastPathComponent
            guard !safeName.isEmpty else { continue }
            let url = directory.appendingPathComponent(safeName)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try font.data.write(to: url, options: .atomic)
            } catch {
                return .writeAttachmentFailed
            }
        }
        return nil
    }
}

private enum ASSFontCacheError: LocalizedError, Sendable {
    case createDirectoryFailed
    case writeAttachmentFailed

    var errorDescription: String? {
        switch self {
        case .createDirectoryFailed:
            "Unable to create the ASS subtitle font cache."
        case .writeAttachmentFailed:
            "Unable to write an embedded ASS subtitle font."
        }
    }
}
