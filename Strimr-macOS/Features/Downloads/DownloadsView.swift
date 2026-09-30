import AppKit
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
                    Label("offline.banner.offline", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                }
            }

            downloadsSection
        }
        .navigationTitle("downloads.title")
    }

    private var storageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("downloads.storage.title").font(.headline)
                Text("downloads.storage.downloads \(formattedBytes(downloadManager.storageSummary.downloadsBytes))")
                    .foregroundStyle(.secondary)
                Text(
                    "downloads.storage.device \(formattedBytes(downloadManager.storageSummary.usedBytes)) \(formattedBytes(downloadManager.storageSummary.totalBytes))",
                )
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
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
                Button("common.actions.delete", systemImage: "trash", role: .destructive) {
                    Task { await downloadManager.delete(item) }
                }
            }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 14) {
            posterView(for: item)
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if isSpoilerProtected(item) {
                        SpoilerProtectionIndicator()
                            .padding(5)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(item.metadata.title).font(.headline).lineLimit(2)
                if let subtitle = item.metadata.subtitle {
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
                qualityView(for: item)
                statusView(for: item)
            }

            Spacer()
            if item.isPlayable {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private func qualityView(for item: DownloadItem) -> some View {
        Text(item.metadata.effectiveQuality.title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func posterView(for item: DownloadItem) -> some View {
        if isSpoilerProtected(item) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        } else if let url = downloadManager.localPosterURL(for: item), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay { Image(systemName: "film").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func statusView(for item: DownloadItem) -> some View {
        switch item.status {
        case .queued:
            Text("downloads.status.queued").foregroundStyle(.secondary)
        case .preparing:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: item.progress).tint(.brandSecondary)
                Text("downloads.status.preparing \(Int((item.progress * 100).rounded()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .downloading:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: item.progress).tint(.brandSecondary)
                Text("downloads.status.downloading \(Int((item.progress * 100).rounded()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .completed:
            Text("downloads.status.completed \(formattedBytes(item.metadata.fileSize ?? item.totalBytes))")
                .foregroundStyle(.secondary)
        case .failed:
            Text(item.errorMessage ?? String(localized: "downloads.status.failed"))
                .foregroundStyle(.red)
        }
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

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func isSpoilerProtected(_ item: DownloadItem) -> Bool {
        downloadManager.localMediaItem(for: item)
            .isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }
}
