import SwiftUI

@MainActor
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDownload: DownloadItem?
    @State private var downloadUsingCellular: DownloadItem?

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
        .listStyle(.insetGrouped)
        .navigationTitle("downloads.title")
        .toolbar { queueToolbar }
        .fullScreenCover(item: $selectedDownload) { item in
            if let localURL = downloadManager.localVideoURL(for: item) {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        localMedia: downloadManager.playbackMedia(for: item),
                        localPlaybackURL: localURL,
                        localExternalSubtitles: downloadManager.localExternalSubtitles(for: item),
                        owner: downloadManager.owner(of: item),
                    ),
                )
            }
        }
        .confirmationDialog(
            "downloads.cellular.confirmation.title",
            isPresented: Binding(
                get: { downloadUsingCellular != nil },
                set: {
                    if !$0 {
                        downloadUsingCellular = nil
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            Button("downloads.cellular.confirmation.confirm") {
                guard let item = downloadUsingCellular else { return }
                downloadUsingCellular = nil
                Task {
                    await downloadManager.useCellularData(for: item)
                }
            }
            Button("common.actions.cancel", role: .cancel) {
                downloadUsingCellular = nil
            }
        } message: {
            Text("downloads.cellular.confirmation.message")
        }
    }

    @ToolbarContentBuilder
    private var queueToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if downloadManager.canPauseAll {
                Button("downloads.actions.pauseAll", systemImage: "pause.fill") {
                    animateQueueChange(downloadManager.pauseAll)
                }
            } else if downloadManager.canResumeAll {
                Button("downloads.actions.resumeAll", systemImage: "play.fill") {
                    animateQueueChange(downloadManager.resumeAll)
                }
            }
        }
    }

    /// Pausing or resuming changes the row height; animating it keeps the list cell in step with its content.
    private func animateQueueChange(_ change: () -> Void) {
        withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), change)
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
            .listRowBackground(Color.clear)
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
            .onTapGesture {
                guard item.isPlayable else { return }
                selectedDownload = item
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task {
                        await downloadManager.delete(item)
                    }
                } label: {
                    Label("common.actions.delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                if downloadManager.canPause(item) {
                    Button {
                        animateQueueChange { downloadManager.pause(item) }
                    } label: {
                        Label("downloads.actions.pause", systemImage: "pause.fill")
                    }
                } else if downloadManager.canResume(item) {
                    Button {
                        animateQueueChange { downloadManager.resume(item) }
                    } label: {
                        Label("downloads.actions.resume", systemImage: "play.fill")
                    }
                }
                if downloadManager.canRetry(item) {
                    Button {
                        downloadManager.retry(item)
                    } label: {
                        Label("common.actions.retry", systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        DownloadRow(
            item: item,
            title: downloadManager.localMediaItem(for: item)
                .spoilerSafeTitle(at: settingsManager.interface.spoilerProtection),
            posterURL: downloadManager.localPosterURL(for: item),
            isSpoilerProtected: isSpoilerProtected(item),
            isWaitingForWiFi: isWaitingForWiFi(item),
            onUseCellular: { downloadUsingCellular = item },
            onRetry: downloadManager.canRetry(item) ? { downloadManager.retry(item) } : nil,
            onResume: downloadManager.canResume(item)
                ? { animateQueueChange { downloadManager.resume(item) } }
                : nil,
            onPause: downloadManager.canPause(item)
                ? { animateQueueChange { downloadManager.pause(item) } }
                : nil,
        )
    }

    private func isWaitingForWiFi(_ item: DownloadItem) -> Bool {
        (item.allowsCellularAccess.map { !$0 } ?? settingsManager.downloads.wifiOnly)
            && downloadManager.isOnWiFi == false
            && item.progress == 0
            && item.taskIdentifier != nil
    }

    private func isSpoilerProtected(_ item: DownloadItem) -> Bool {
        downloadManager.localMediaItem(for: item)
            .isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }
}
