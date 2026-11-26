import SwiftUI

/// Download state shown on a detail page, for one movie or episode or for the episodes queued from a series or season.
struct DownloadActivity: Equatable {
    enum Phase: Equatable {
        case queued
        /// Plex transcodes the file on the server before the transfer can start.
        case preparing
        case transferring
        case completed
        /// Some episodes are downloaded and nothing is running.
        case partial
        case paused
        case failed
    }

    var phase: Phase
    /// Nil until there is something to show, or when the server sends no size.
    var progress: Double?
    var completedCount: Int
    var totalCount: Int

    var isInProgress: Bool {
        switch phase {
        case .queued, .preparing, .transferring:
            true
        case .paused, .completed, .partial, .failed:
            false
        }
    }

    init(phase: Phase, progress: Double?, completedCount: Int, totalCount: Int) {
        self.phase = phase
        self.progress = progress
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    init(item: DownloadItem) {
        let progress = item.progress > 0 ? min(item.progress, 1) : nil
        switch item.status {
        case .queued:
            self.init(phase: .queued, progress: nil, completedCount: 0, totalCount: 1)
        case .preparing:
            self.init(phase: .preparing, progress: progress, completedCount: 0, totalCount: 1)
        case .downloading:
            self.init(phase: .transferring, progress: progress, completedCount: 0, totalCount: 1)
        case .paused:
            self.init(phase: .paused, progress: progress, completedCount: 0, totalCount: 1)
        case .completed:
            self.init(phase: .completed, progress: 1, completedCount: 1, totalCount: 1)
        case .failed:
            self.init(phase: .failed, progress: nil, completedCount: 0, totalCount: 1)
        }
    }

    /// Progress covers the episodes that were queued, not the whole series. `expectedCount` (the episode count of
    /// the series or season) only decides whether the downloaded episodes cover all of it.
    init?(episodes: [DownloadItem], expectedCount: Int?) {
        let latest = Dictionary(grouping: episodes) { $0.identity?.itemID ?? $0.id }
            .values
            .compactMap { $0.max { $0.createdAt < $1.createdAt } }
        guard !latest.isEmpty else { return nil }

        let completedCount = latest.count(where: { $0.status == .completed })
        let statuses = Set(latest.map(\.status))
        let phase: Phase = if statuses.contains(.downloading) {
            .transferring
        } else if statuses.contains(.preparing) {
            .preparing
        } else if statuses.contains(.queued) {
            .queued
        } else if statuses.contains(.paused) {
            .paused
        } else if completedCount == 0 {
            .failed
        } else if completedCount < max(latest.count, expectedCount ?? 0) {
            .partial
        } else {
            .completed
        }

        let progress: Double? = switch phase {
        case .queued, .preparing, .transferring, .paused:
            Self.aggregateProgress(of: latest, completedCount: completedCount)
        case .completed:
            1
        case .partial, .failed:
            nil
        }
        self.init(phase: phase, progress: progress, completedCount: completedCount, totalCount: latest.count)
    }

    private static func aggregateProgress(of items: [DownloadItem], completedCount: Int) -> Double? {
        // Preparation progress is left out: it restarts at zero when the transfer begins.
        let transferred = items
            .filter { $0.status == .downloading || $0.status == .paused }
            .reduce(0) { $0 + min(max($1.progress, 0), 1) }
        let value = (Double(completedCount) + transferred) / Double(items.count)
        guard value > 0 else { return nil }
        // Rounding must not fill the ring while an episode is still running.
        return min(value, 0.99)
    }
}

extension DownloadActivity {
    var ring: DownloadProgressRing.Value? {
        guard let progress else { return nil }
        switch phase {
        case .preparing:
            return .init(progress: progress, style: .serverPreparation)
        case .transferring:
            return .init(progress: progress, style: .transfer)
        case .queued:
            // A series keeps its ring between two episodes.
            return totalCount > 1 ? .init(progress: progress, style: .transfer) : nil
        case .paused:
            return .init(progress: progress, style: .transfer)
        case .completed, .partial, .failed:
            return nil
        }
    }

    var showsSpinner: Bool {
        (phase == .preparing || phase == .transferring) && progress == nil
    }

    var systemImage: String {
        switch phase {
        case .queued: "clock"
        case .paused: "pause.circle"
        case .preparing, .transferring: "arrow.down.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .partial: "arrow.down.circle.fill"
        case .failed: "exclamationmark.circle"
        }
    }

    var phaseTitle: LocalizedStringResource? {
        switch phase {
        case .queued: "downloads.status.queued"
        case .preparing: "downloads.phase.preparing"
        case .transferring: "downloads.phase.transferring"
        case .paused: "downloads.status.paused"
        case .completed, .partial, .failed: nil
        }
    }

    var accessibilityValue: String {
        var parts: [String] = []
        if let phaseTitle {
            parts.append(String(localized: phaseTitle))
        }
        if let progress, isInProgress || phase == .paused {
            parts.append(progress.formatted(.percent.precision(.fractionLength(0))))
        }
        if totalCount > 1 {
            parts.append(String(localized: "offline.detail.downloadedEpisodes \(completedCount) \(totalCount)"))
        }
        return parts.joined(separator: ", ")
    }
}
