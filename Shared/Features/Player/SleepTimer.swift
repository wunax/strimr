import Foundation
import Observation

enum SleepTimerMode: Hashable {
    case duration(minutes: Int)
    case endOfItem
    case endOfChapter

    static let durationMinutes = [15, 30, 45, 60, 90, 120]

    static func available(isLive: Bool, hasChapters: Bool) -> [SleepTimerMode] {
        var modes: [SleepTimerMode] = []
        if !isLive {
            modes.append(.endOfItem)
        }
        if !isLive, hasChapters {
            modes.append(.endOfChapter)
        }
        return modes + durationMinutes.map { .duration(minutes: $0) }
    }

    func title(for mediaKind: MediaKind?) -> String {
        switch self {
        case let .duration(minutes):
            Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        case .endOfItem:
            switch mediaKind {
            case .episode:
                String(localized: "player.sleepTimer.endOfEpisode")
            case .movie:
                String(localized: "player.sleepTimer.endOfMovie")
            default:
                String(localized: "player.sleepTimer.endOfItem")
            }
        case .endOfChapter:
            String(localized: "player.sleepTimer.endOfChapter")
        }
    }
}

/// Pauses playback after a delay or at a boundary of the current item. Lives as long as the player, so it
/// keeps running across queue items and ends when the player closes.
@MainActor
@Observable
final class SleepTimer {
    static let extensionMinutes = 15
    static let promptSeconds = 30
    static let fadeSeconds: TimeInterval = 5
    /// Pausing just before a boundary leaves the player on a real frame: resuming plays the last moment and
    /// lets the usual end-of-item flow (next episode, autoplay) take over.
    static let boundaryLead: TimeInterval = 1
    /// Position steps larger than this are seeks, which must not trigger a boundary pause.
    static let maximumPlaybackStep: TimeInterval = 3

    private(set) var mode: SleepTimerMode?
    private(set) var deadline: Date?
    private(set) var promptDeadline: Date?

    var isActive: Bool {
        mode != nil
    }

    var isPromptPresented: Bool {
        promptDeadline != nil
    }

    @ObservationIgnored var pausePlayback: () -> Void = {}
    @ObservationIgnored var isPlaybackActive: () -> Bool = { true }
    @ObservationIgnored var setVolumeAttenuation: (Float) -> Void = { _ in }
    /// Boundary pauses happen without a prompt, so the player tells whoever is still watching why it stopped.
    @ObservationIgnored var onBoundaryPause: () -> Void = {}

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastPosition: Double?
    @ObservationIgnored private var attenuation: Float = 1
    @ObservationIgnored private var restoresVolumeOnResume = false

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func start(_ mode: SleepTimerMode) {
        reset()
        self.mode = mode
        if case let .duration(minutes) = mode {
            schedule(deadline: now().addingTimeInterval(TimeInterval(minutes * 60)))
        }
    }

    func extend() {
        guard let deadline, !isPromptPresented else { return }
        schedule(deadline: deadline.addingTimeInterval(TimeInterval(Self.extensionMinutes * 60)))
    }

    func cancel() {
        reset()
    }

    func continueAfterPrompt() {
        guard isPromptPresented, let mode else { return }
        start(mode)
    }

    func pauseNow() {
        guard isActive else { return }
        pauseAndFinish()
    }

    func handlePlaybackStateChange(isPaused: Bool) {
        if isPaused {
            // Pausing by hand while asked "still watching?" is the answer the timer was waiting for.
            if isPromptPresented {
                reset()
            }
        } else if restoresVolumeOnResume {
            restoreVolume()
        }
    }

    func handlePosition(_ position: Double, duration: Double?, chapters: [MediaChapter]) {
        defer { lastPosition = position }
        guard let mode, let previous = lastPosition else { return }
        if case .duration = mode {
            return
        }

        let step = position - previous
        guard step != 0 else { return }
        guard step > 0, step <= Self.maximumPlaybackStep else {
            restoreVolume()
            return
        }
        guard let boundary = boundary(for: mode, at: previous, duration: duration, chapters: chapters) else {
            return
        }

        let pausePoint = boundary - Self.boundaryLead
        if position >= pausePoint {
            pauseAndFinish()
            onBoundaryPause()
        } else {
            applyAttenuation(Float(min((pausePoint - position) / Self.fadeSeconds, 1)))
        }
    }

    /// Playback reached the end without crossing the pause point, e.g. after a credits skip jumped there.
    /// Returns whether the timer claimed the end, in which case the caller must not advance.
    func consumePlaybackEnd() -> Bool {
        guard mode == .endOfItem || mode == .endOfChapter else { return false }
        reset()
        return true
    }

    func expire() {
        guard case .duration = mode, !isPromptPresented else { return }
        deadline = nil
        guard isPlaybackActive() else {
            pauseAndFinish()
            return
        }

        let promptDeadline = now().addingTimeInterval(TimeInterval(Self.promptSeconds))
        self.promptDeadline = promptDeadline
        task = Task { [weak self] in
            await self?.runPromptCountdown(until: promptDeadline)
        }
    }

    func expirePrompt() {
        guard isPromptPresented else { return }
        pauseAndFinish()
    }

    private func schedule(deadline: Date) {
        task?.cancel()
        self.deadline = deadline
        task = Task { [weak self] in
            guard let self, await sleep(until: deadline) else { return }
            expire()
        }
    }

    private func runPromptCountdown(until promptDeadline: Date) async {
        guard await sleep(until: promptDeadline.addingTimeInterval(-Self.fadeSeconds)) else { return }
        while true {
            let remaining = promptDeadline.timeIntervalSince(now())
            guard remaining > 0 else { break }
            applyAttenuation(Float(remaining / Self.fadeSeconds))
            guard await sleep(until: now().addingTimeInterval(0.1)) else { return }
        }
        expirePrompt()
    }

    private func sleep(until date: Date) async -> Bool {
        let interval = date.timeIntervalSince(now())
        if interval > 0 {
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }

    private func boundary(
        for mode: SleepTimerMode,
        at position: Double,
        duration: Double?,
        chapters: [MediaChapter],
    ) -> Double? {
        switch mode {
        case .duration:
            nil
        case .endOfItem:
            duration.flatMap { $0 > 0 ? $0 : nil }
        case .endOfChapter:
            chapters.first { $0.contains(time: position) }?.endTime
        }
    }

    private func applyAttenuation(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        guard clamped != attenuation else { return }
        attenuation = clamped
        setVolumeAttenuation(clamped)
    }

    private func restoreVolume() {
        restoresVolumeOnResume = false
        applyAttenuation(1)
    }

    private func finish() {
        task?.cancel()
        task = nil
        mode = nil
        deadline = nil
        promptDeadline = nil
    }

    private func reset() {
        finish()
        restoreVolume()
    }

    /// The volume stays down until playback resumes: restoring it right away could let a second of full
    /// volume through before the pause lands.
    private func pauseAndFinish() {
        finish()
        pausePlayback()
        restoresVolumeOnResume = attenuation < 1
    }
}
