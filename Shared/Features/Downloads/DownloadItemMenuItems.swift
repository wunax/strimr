import SwiftUI

/// Actions on an existing download of a movie or an episode, shown in place of a new download.
struct DownloadItemMenuItems: View {
    @Environment(DownloadManager.self) private var downloadManager
    let item: DownloadItem
    let isServerReachable: Bool
    let onPlay: (LocalPlaybackRequest) -> Void

    var body: some View {
        if item.isPlayable, let request = downloadManager.localPlaybackRequest(for: item) {
            Button("offline.detail.playDownloaded", systemImage: "play.fill") {
                onPlay(request)
            }
        }
        if downloadManager.canPause(item) {
            Button("downloads.actions.pause", systemImage: "pause.fill") {
                downloadManager.pause(item)
            }
        }
        if isServerReachable, downloadManager.canResume(item) {
            Button("downloads.actions.resume", systemImage: "play.fill") {
                downloadManager.resume(item)
            }
        }
        if isServerReachable, downloadManager.canRetry(item) {
            Button("common.actions.retry", systemImage: "arrow.clockwise") {
                downloadManager.retry(item)
            }
        }
        Button(
            item.status.isUnfinished ? "downloads.actions.cancel" : "downloads.actions.delete",
            systemImage: item.status.isUnfinished ? "xmark.circle" : "trash",
            role: .destructive,
        ) {
            Task { await downloadManager.delete(item) }
        }
    }
}
