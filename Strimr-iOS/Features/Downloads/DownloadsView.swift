import SwiftUI
import UIKit

@MainActor
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlexAPIContext.self) private var context
    @State private var selectedDownload: DownloadItem?

    var body: some View {
        List {
            storageSection

            if downloadManager.isOffline {
                Section {
                    Label("downloads.offline.banner", systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.semibold))
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
                        localMedia: downloadManager.localMediaItem(for: item),
                        localPlaybackURL: localURL,
                        context: context,
                    ),
                )
            }
        }
    }

    private var storageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("downloads.storage.title")
                    .font(.headline)

                Text("downloads.storage.downloads \(formattedBytes(downloadManager.storageSummary.downloadsBytes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(
                    "downloads.storage.device \(formattedBytes(downloadManager.storageSummary.usedBytes)) \(formattedBytes(downloadManager.storageSummary.totalBytes))",
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var downloadsSection: some View {
        if downloadManager.sortedItems.isEmpty {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("downloads.empty.title")
                        .font(.headline)
                    Text("downloads.empty.message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else {
            Section("downloads.list.title") {
                ForEach(downloadManager.sortedItems) { item in
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
            }
        }
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            posterView(for: item)
                .frame(width: 64, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.metadata.title)
                    .font(.headline)
                    .lineLimit(2)

                if let subtitle = item.metadata.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                statusView(for: item)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func posterView(for item: DownloadItem) -> some View {
        if let posterURL = downloadManager.localPosterURL(for: item),
           let image = UIImage(contentsOfFile: posterURL.path)
        {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func statusView(for item: DownloadItem) -> some View {
        switch item.status {
        case .queued:
            Text("downloads.status.queued")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: item.progress)
                    .tint(.brandSecondary)

                Text("downloads.status.downloading \(Int((item.progress * 100).rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            let size = item.metadata.fileSize ?? item.totalBytes
            Text("downloads.status.completed \(formattedBytes(size))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text("downloads.status.failed")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
