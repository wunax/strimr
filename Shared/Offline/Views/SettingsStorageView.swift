import SwiftUI

struct SettingsStorageView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @State private var sizes = OfflineStorageSizes()
    @State private var isConfirmingCacheClear = false
    @State private var isConfirmingOtherDownloadsDeletion = false

    var body: some View {
        List {
            Section {
                LabeledContent(
                    "settings.storage.downloads",
                    value: formatted(downloadManager.storageSummary.downloadsBytes),
                )
                LabeledContent("settings.storage.pinned", value: formatted(sizes.pinnedBytes))
                LabeledContent("settings.storage.cache", value: formatted(sizes.cacheBytes))
            } footer: {
                Text("settings.storage.pinned.footer")
            }

            Section {
                Picker(
                    "settings.storage.cacheLimit",
                    selection: Binding(
                        get: { settingsManager.downloads.offlineCacheLimitMB },
                        set: { settingsManager.setOfflineCacheLimit(megabytes: $0) },
                    ),
                ) {
                    ForEach(OfflineCacheLimit.allCases) { limit in
                        Text(limit.title).tag(limit.rawValue)
                    }
                }

                Button("settings.storage.clearCache", role: .destructive) {
                    isConfirmingCacheClear = true
                }
            } footer: {
                Text("settings.storage.cache.footer")
            }

            if !otherDownloads.isEmpty {
                Section {
                    LabeledContent(
                        "offline.downloads.others",
                        value: "\(otherDownloads.count) • \(formatted(otherDownloadsBytes))",
                    )
                    Button("settings.storage.deleteOtherDownloads", role: .destructive) {
                        isConfirmingOtherDownloadsDeletion = true
                    }
                } footer: {
                    Text("offline.downloads.others.footer")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("settings.storage.title")
        .task { refreshSizes() }
        .confirmationDialog(
            "settings.storage.clearCache",
            isPresented: $isConfirmingCacheClear,
            titleVisibility: .visible,
        ) {
            Button("settings.storage.clearCache", role: .destructive) {
                offlineCoordinator.clearCache()
                refreshSizes()
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("settings.storage.clearCache.message")
        }
        .confirmationDialog(
            "settings.storage.deleteOtherDownloads",
            isPresented: $isConfirmingOtherDownloadsDeletion,
            titleVisibility: .visible,
        ) {
            Button("common.actions.delete", role: .destructive) {
                Task {
                    await downloadManager.deleteOtherDownloads()
                    refreshSizes()
                }
            }
            Button("common.actions.cancel", role: .cancel) {}
        }
    }

    /// Downloads of other profiles or accounts; only meaningful while someone is signed in.
    private var otherDownloads: [DownloadItem] {
        downloadManager.activeOwnerIDs.isEmpty ? [] : downloadManager.otherItems
    }

    private var otherDownloadsBytes: Int64 {
        otherDownloads.reduce(0) { $0 + ($1.metadata.fileSize ?? $1.totalBytes) }
    }

    private func refreshSizes() {
        sizes = offlineCoordinator.storageSizes()
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
