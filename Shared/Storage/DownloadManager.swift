import Foundation
import Observation

enum DownloadState {
    case notDownloaded
    case downloading
    case downloaded
}

@Observable
class DownloadTask: Identifiable {
    let id = UUID()
    let task: URLSessionDownloadTask
    let title: String
    let artworkPath: String?
    let type: PlexItemType?
    var progress: Double = 0.0
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
    let resolution: String?
    let bitrate: Int?

    init(task: URLSessionDownloadTask, title: String, artworkPath: String? = nil, type: PlexItemType? = nil, resolution: String? = nil, bitrate: Int? = nil) {
        self.task = task
        self.title = title
        self.artworkPath = artworkPath
        self.type = type
        self.resolution = resolution
        self.bitrate = bitrate
    }
}

struct DownloadedMedia: Codable, Identifiable {
    let id: String // ratingKey
    let title: String
    let downloadPath: String // The Plex API path
    let localFileName: String // The filename on disk
    let artworkPath: String?
    let type: PlexItemType
    let resolution: String?
    let bitrate: Int?
}

@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    var activeDownloads: [URL: DownloadTask] = [:]
    var activeDownloadsArray: [DownloadTask] {
        activeDownloads.values.sorted { $0.title < $1.title }
    }
    var downloadedMedia: [DownloadedMedia] = []

    // Map to store media info for active downloads so we can save it upon completion
    private var pendingMediaInfo: [URL: DownloadedMedia] = [:]

    @ObservationIgnored
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override private init() {
        super.init()
        loadDownloadedMedia()
    }

    func startDownload(media: MediaItem, url: URL) {
        let task = urlSession.downloadTask(with: url)
        let downloadTask = DownloadTask(
            task: task,
            title: media.title,
            artworkPath: media.thumbPath ?? media.artPath,
            type: media.type
        )
        activeDownloads[url] = downloadTask

        // Create a placeholder info
        let info = DownloadedMedia(
            id: media.id,
            title: media.title,
            downloadPath: media.downloadPath ?? "",
            localFileName: url.lastPathComponent,
            artworkPath: media.thumbPath ?? media.artPath,
            type: media.type,
            resolution: media.videoResolution,
            bitrate: media.bitrate
        )
        pendingMediaInfo[url] = info

        task.resume()
    }

    // Legacy support for just URL
    func startDownload(url: URL, title: String) {
        let task = urlSession.downloadTask(with: url)
        let downloadTask = DownloadTask(task: task, title: title)
        activeDownloads[url] = downloadTask
        task.resume()
    }

    func cancelDownload(url: URL) {
        if let downloadTask = activeDownloads[url] {
            downloadTask.task.cancel()
            activeDownloads[url] = nil
            pendingMediaInfo[url] = nil
        }
    }

    func deleteDownload(media: DownloadedMedia) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localURL = documents.appendingPathComponent(media.localFileName)
        try? FileManager.default.removeItem(at: localURL)

        downloadedMedia.removeAll { $0.id == media.id }
        saveDownloadedMedia()
    }

    // Legacy delete by URL
    func deleteDownload(url: URL) {
        let destination = localFilePath(for: url)
        try? FileManager.default.removeItem(at: destination)

        // Try to remove from list if we can find it by filename
        let filename = destination.lastPathComponent
        if let index = downloadedMedia.firstIndex(where: { $0.localFileName == filename }) {
            downloadedMedia.remove(at: index)
            saveDownloadedMedia()
        }
    }

    func isDownloaded(url: URL) -> Bool {
        let destination = localFilePath(for: url)
        return FileManager.default.fileExists(atPath: destination.path)
    }

    func isDownloaded(mediaId: String) -> Bool {
        return downloadedMedia.contains(where: { $0.id == mediaId })
    }

    func getDownloadedMedia(byId id: String) -> DownloadedMedia? {
        return downloadedMedia.first(where: { $0.id == id })
    }

    func localFilePath(for url: URL) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent(url.lastPathComponent)
    }

    func downloadState(for url: URL) -> DownloadState {
        if isDownloaded(url: url) { return .downloaded }
        if activeDownloads[url] != nil { return .downloading }
        return .notDownloaded
    }

    private func saveDownloadedMedia() {
        if let data = try? JSONEncoder().encode(downloadedMedia) {
            UserDefaults.standard.set(data, forKey: "downloadedMedia")
        }
    }

    private func loadDownloadedMedia() {
        if let data = UserDefaults.standard.data(forKey: "downloadedMedia"),
           let items = try? JSONDecoder().decode([DownloadedMedia].self, from: data) {
            downloadedMedia = items
        }
    }

    // Helper to register a download manually if needed (used by MediaDetailViewModel completion)
    func registerDownload(media: MediaItem, localFileName: String) {
        let item = DownloadedMedia(
            id: media.id,
            title: media.title,
            downloadPath: media.downloadPath ?? "",
            localFileName: localFileName,
            artworkPath: media.thumbPath ?? media.artPath,
            type: media.type,
            resolution: media.videoResolution,
            bitrate: media.bitrate
        )
        if !downloadedMedia.contains(where: { $0.id == item.id }) {
            downloadedMedia.append(item)
            saveDownloadedMedia()
        }
    }

    var totalDownloadsSize: Int64 {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return downloadedMedia.reduce(0) { total, item in
            let url = documents.appendingPathComponent(item.localFileName)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return total + (attributes?[.size] as? Int64 ?? 0)
        }
    }

    var deviceFreeSpace: Int64 {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: documents.path)
        return attributes?[.systemFreeSize] as? Int64 ?? 0
    }

    func fileSize(for item: DownloadedMedia) -> Int64? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = documents.appendingPathComponent(item.localFileName)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int64
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let sourceURL = downloadTask.originalRequest?.url else { return }

        let destinationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(sourceURL.lastPathComponent)

        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)

            Task { @MainActor in
                if let info = self.pendingMediaInfo[sourceURL] {
                    if !self.downloadedMedia.contains(where: { $0.id == info.id }) {
                        self.downloadedMedia.append(info)
                        self.saveDownloadedMedia()
                    }
                    self.pendingMediaInfo[sourceURL] = nil
                }
                self.activeDownloads[sourceURL] = nil
            }
        } catch {
            print("File move error: \(error)")
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let sourceURL = downloadTask.originalRequest?.url else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            guard let taskModel = self.activeDownloads[sourceURL] else { return }
            taskModel.progress = progress
            taskModel.downloadedBytes = totalBytesWritten
            taskModel.totalBytes = totalBytesExpectedToWrite
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let sourceURL = task.originalRequest?.url else { return }

        if let error = error {
            print("Download error: \(error)")
        }

        Task { @MainActor in
            self.activeDownloads[sourceURL] = nil
            self.pendingMediaInfo[sourceURL] = nil
        }
    }
}



















