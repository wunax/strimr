import AppKit
import SwiftUI

@MainActor
struct MacDownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(MacAppModel.self) private var appModel

    var body: some View {
        List {
            storageSection

            if downloadManager.isOffline {
                Section {
                    Label("downloads.offline.banner", systemImage: "wifi.slash")
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

    @ViewBuilder
    private var downloadsSection: some View {
        if downloadManager.sortedItems.isEmpty {
            ContentUnavailableView(
                "downloads.empty.title",
                systemImage: "arrow.down.circle",
                description: Text("downloads.empty.message"),
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            Section("downloads.list.title") {
                ForEach(downloadManager.sortedItems) { item in
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
            }
        }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 14) {
            posterView(for: item)
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                Text(item.metadata.title).font(.headline).lineLimit(2)
                if let subtitle = item.metadata.subtitle {
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
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

    @ViewBuilder
    private func posterView(for item: DownloadItem) -> some View {
        if let url = downloadManager.localPosterURL(for: item), let image = NSImage(contentsOf: url) {
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
        appModel.showDownloadedPlayer(media: downloadManager.localMediaItem(for: item), url: url)
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
