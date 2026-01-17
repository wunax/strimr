import SwiftUI
import Observation

struct DownloadsView: View {
    @State private var downloadManager: DownloadManager
    @Environment(PlexAPIContext.self) private var context
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MainCoordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL

    init(downloadManager: DownloadManager = .shared) {
        _downloadManager = State(initialValue: downloadManager)
    }

    var body: some View {
        List {
            if !downloadManager.activeDownloads.isEmpty {
                Section("downloads.active") {
                    let active = downloadManager.activeDownloadsArray
                    ForEach(active) { task in
                        mediaRow(
                            title: task.title,
                            type: task.type,
                            artworkPath: task.artworkPath,
                            progress: task.progress,
                            totalBytes: task.totalBytes,
                            downloadedBytes: task.downloadedBytes,
                            resolution: task.resolution,
                            bitrate: task.bitrate
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            if index < active.count {
                                let task = active[index]
                                if let url = task.task.originalRequest?.url {
                                    downloadManager.cancelDownload(url: url)
                                }
                            }
                        }
                    }
                }
            }

            if downloadManager.downloadedMedia.isEmpty && downloadManager.activeDownloads.isEmpty {
                Section {
                    Text("downloads.empty")
                        .foregroundStyle(.secondary)
                }
            } else if !downloadManager.downloadedMedia.isEmpty {
                Section("downloads.completed") {
                    let completed = downloadManager.downloadedMedia
                    ForEach(completed) { item in
                        Button {
                            coordinator.showMediaDetailReplacingDownloads(mediaItem(for: item))
                        } label: {
                            HStack {
                                mediaRow(
                                    title: item.title,
                                    type: item.type,
                                    artworkPath: item.artworkPath,
                                    fileSize: downloadManager.fileSize(for: item),
                                    resolution: item.resolution,
                                    bitrate: item.bitrate
                                )
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            if index < completed.count {
                                let item = completed[index]
                                downloadManager.deleteDownload(media: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("downloads.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                storageHeader
            }
        }
    }

    private var storageHeader: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Text("downloads.storage.total")
                    .foregroundStyle(.secondary)
                Text(formatBytes(downloadManager.totalDownloadsSize))
                    .fontWeight(.semibold)
            }
            HStack(spacing: 4) {
                Text("downloads.storage.free")
                    .foregroundStyle(.secondary)
                Text(formatBytes(downloadManager.deviceFreeSpace))
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @ViewBuilder
    private func mediaRow(
        title: String,
        type: PlexItemType?,
        artworkPath: String?,
        progress: Double? = nil,
        fileSize: Int64? = nil,
        totalBytes: Int64? = nil,
        downloadedBytes: Int64? = nil,
        resolution: String? = nil,
        bitrate: Int? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let thumb = artworkPath,
                   let url = imageURL(path: thumb) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                } else {
                    Color.gray.opacity(0.2)
                        .frame(width: 60, height: 90)
                        .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)

                    if let type = type {
                        Text(type.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let resolution = resolution {
                            Text(resolution.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.brandPrimary.opacity(0.2))
                                .foregroundStyle(.brandPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if let bitrate = bitrate {
                            Text("\(String(format: "%.1f", Double(bitrate) / 1000)) Mbps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let fileSize = fileSize {
                            Text(formatBytes(fileSize))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }

            if let progress = progress {
                ProgressView(value: progress)
                    .tint(.brandPrimary)
            }

            if let totalBytes = totalBytes, let downloadedBytes = downloadedBytes, totalBytes > 0 {
                Text("\(String(format: "%.2f", Double(downloadedBytes) / 1_000_000_000)) / \(String(format: "%.2f", Double(totalBytes) / 1_000_000_000)) GB")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }


    private func handlePlay(_ item: DownloadedMedia) {
        let player = settingsManager.playback.player
        if player.isExternal {
            Task { @MainActor in
                await launchExternalPlayback(ratingKey: item.id)
            }
        } else {
            coordinator.showPlayer(for: item.id, downloadPath: item.downloadPath)
        }
    }

    @MainActor
    private func launchExternalPlayback(ratingKey: String) async {
        do {
            let launcher = ExternalPlaybackLauncher(context: context)
            let url = try await launcher.infuseURL(for: ratingKey)
            openURL(url)
        } catch {
            debugPrint("Failed to launch external playback:", error)
        }
    }

    private func imageURL(path: String) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        return imageRepository.transcodeImageURL(path: path, width: 200, height: 300)
    }

    private func mediaItem(for item: DownloadedMedia) -> MediaItem {
        MediaItem(
            id: item.id,
            guid: "",
            summary: nil,
            title: item.title,
            type: item.type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            rating: nil,
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: item.artworkPath,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
            downloadPath: item.downloadPath,
            videoResolution: item.resolution,
            bitrate: item.bitrate
        )
    }
}
