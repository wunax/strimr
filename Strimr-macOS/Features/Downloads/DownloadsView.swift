import SwiftUI

@MainActor
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(AppModel.self) private var appModel

    var body: some View {
        List {
            storageSection

            if !offlineCoordinator.availability.hasNetworkPath {
                Section {
                    DownloadsOfflineBanner()
                }
            }

            downloadsSection
        }
        .navigationTitle("downloads.title")
    }

    private var storageSection: some View {
        Section {
            DownloadsStorageSummaryView(summary: downloadManager.storageSummary)
        }
    }

    /// Signed in: the user's downloads, then those of other profiles or accounts. Signed out: everything.
    private var primaryItems: [DownloadItem] {
        downloadManager.activeOwnerIDs.isEmpty ? downloadManager.sortedItems : downloadManager.sortedOwnedItems
    }

    private var otherItems: [DownloadItem] {
        downloadManager.activeOwnerIDs.isEmpty ? [] : downloadManager.sortedOtherItems
    }

    @ViewBuilder
    private var downloadsSection: some View {
        if primaryItems.isEmpty, otherItems.isEmpty {
            ContentUnavailableView(
                "downloads.empty.title",
                systemImage: "arrow.down.circle",
                description: Text("downloads.empty.message"),
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            if !primaryItems.isEmpty {
                Section("downloads.list.title") {
                    ForEach(primaryItems, content: interactiveRow)
                }
            }
            if !otherItems.isEmpty {
                Section {
                    ForEach(otherItems, content: interactiveRow)
                } header: {
                    Text("offline.downloads.others")
                } footer: {
                    Text("offline.downloads.others.footer")
                }
            }
        }
    }

    private func interactiveRow(_ item: DownloadItem) -> some View {
        downloadRow(item)
            .contentShape(Rectangle())
            .onTapGesture { play(item) }
            .contextMenu {
                if item.isPlayable {
                    Button("common.actions.play", systemImage: "play.fill") { play(item) }
                }
                if downloadManager.canRetry(item) {
                    Button("common.actions.retry", systemImage: "arrow.clockwise") {
                        downloadManager.retry(item)
                    }
                }
                Button("common.actions.delete", systemImage: "trash", role: .destructive) {
                    Task { await downloadManager.delete(item) }
                }
            }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        DownloadRow(
            item: item,
            posterURL: downloadManager.localPosterURL(for: item),
            isSpoilerProtected: isSpoilerProtected(item),
            onRetry: downloadManager.canRetry(item) ? { downloadManager.retry(item) } : nil,
        )
    }

    private func play(_ item: DownloadItem) {
        guard item.isPlayable, let url = downloadManager.localVideoURL(for: item) else { return }
        appModel.showDownloadedPlayer(
            media: downloadManager.playbackMedia(for: item),
            url: url,
            externalSubtitles: downloadManager.localExternalSubtitles(for: item),
            owner: downloadManager.owner(of: item),
        )
    }

    private func isSpoilerProtected(_ item: DownloadItem) -> Bool {
        downloadManager.localMediaItem(for: item)
            .isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }
}
