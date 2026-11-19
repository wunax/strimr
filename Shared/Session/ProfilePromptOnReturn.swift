import Foundation

/// Decides when the profile picker comes back as the app returns from the background, for apps that stay in memory
/// for days, such as on Apple TV.
struct ProfilePromptOnReturn {
    static let absenceThreshold: TimeInterval = 15 * 60

    private(set) var backgroundedAt: Date?

    mutating func didEnterBackground(at date: Date) {
        backgroundedAt = date
    }

    /// Consumes the absence, so the inactive and active phases that follow a return prompt only once.
    mutating func shouldPrompt(at date: Date, isPlaybackActive: Bool) -> Bool {
        guard let backgroundedAt else { return false }
        self.backgroundedAt = nil
        return !isPlaybackActive && date.timeIntervalSince(backgroundedAt) >= Self.absenceThreshold
    }

    mutating func cancel() {
        backgroundedAt = nil
    }
}
