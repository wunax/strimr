import SwiftUI

@MainActor
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
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
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        DownloadRow(
            item: item,
            posterURL: downloadManager.localPosterURL(for: item),
            isSpoilerProtected: isSpoilerProtected(item),
            isWaitingForWiFi: isWaitingForWiFi(item),
            onUseCellular: { downloadUsingCellular = item },
            onRetry: downloadManager.canRetry(item) ? { downloadManager.retry(item) } : nil,
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
