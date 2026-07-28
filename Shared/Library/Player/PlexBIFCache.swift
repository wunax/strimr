import CryptoKit
import Foundation

nonisolated struct PlexBIFCacheMetadata: Codable, Sendable {
    var validators: PlexBIFValidators
    var lastValidatedAt: Date
    var lastAccessedAt: Date
    var byteCount: Int64
}

nonisolated struct PlexBIFCacheEntry: Sendable {
    let fileURL: URL
    let metadata: PlexBIFCacheMetadata
}

actor PlexBIFDiskCache {
    static let shared = PlexBIFDiskCache()

    private let maximumByteCount: Int64 = 250 * 1024 * 1024
    private let fileManager = FileManager.default
    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PlexBIF", isDirectory: true)
    }

    nonisolated static func key(
        serverIdentity: String,
        partID: Int,
        intervalMilliseconds: Int,
    ) -> String {
        let value = "\(serverIdentity)|\(partID)|\(intervalMilliseconds)|bif-v0-parser-1"
        return SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func entry(for key: String) throws -> PlexBIFCacheEntry? {
        try ensureDirectory()
        let fileURL = bifURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        var metadata = (try? loadMetadata(for: key)) ?? PlexBIFCacheMetadata(
            validators: PlexBIFValidators(),
            lastValidatedAt: .distantPast,
            lastAccessedAt: .distantPast,
            byteCount: byteCount,
        )
        metadata.lastAccessedAt = Date()
        metadata.byteCount = byteCount
        try saveMetadata(metadata, for: key)
        return PlexBIFCacheEntry(fileURL: fileURL, metadata: metadata)
    }

    func store(
        stagedFileURL: URL,
        key: String,
        validators: PlexBIFValidators,
    ) throws -> PlexBIFArchive {
        try ensureDirectory()
        _ = try PlexBIFArchive(fileURL: stagedFileURL)
        let destinationURL = bifURL(for: key)

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagedFileURL,
                backupItemName: nil,
                options: [],
            )
        } else {
            try fileManager.moveItem(at: stagedFileURL, to: destinationURL)
        }

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let now = Date()
        try saveMetadata(
            PlexBIFCacheMetadata(
                validators: validators,
                lastValidatedAt: now,
                lastAccessedAt: now,
                byteCount: byteCount,
            ),
            for: key,
        )
        try pruneIfNeeded()
        return try PlexBIFArchive(fileURL: destinationURL)
    }

    func markValidated(
        key: String,
        validators: PlexBIFValidators,
    ) throws {
        guard var metadata = try loadMetadata(for: key) else { return }
        metadata.validators = validators
        metadata.lastValidatedAt = Date()
        metadata.lastAccessedAt = Date()
        try saveMetadata(metadata, for: key)
    }

    func remove(key: String) {
        try? fileManager.removeItem(at: bifURL(for: key))
        try? fileManager.removeItem(at: metadataURL(for: key))
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
        )
    }

    private func loadMetadata(for key: String) throws -> PlexBIFCacheMetadata? {
        let url = metadataURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            PlexBIFCacheMetadata.self,
            from: Data(contentsOf: url),
        )
    }

    private func saveMetadata(
        _ metadata: PlexBIFCacheMetadata,
        for key: String,
    ) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL(for: key), options: .atomic)
    }

    private func pruneIfNeeded() throws {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
        )
        let bifURLs = urls.filter { $0.pathExtension == "bif" }
        var entries: [(url: URL, key: String, size: Int64, accessedAt: Date)] = []
        var totalByteCount: Int64 = 0

        for url in bifURLs {
            let key = url.deletingPathExtension().lastPathComponent
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values.fileSize ?? 0)
            let accessedAt = (try? loadMetadata(for: key)?.lastAccessedAt) ?? .distantPast
            entries.append((url, key, size, accessedAt))
            totalByteCount += size
        }

        for entry in entries.sorted(by: { $0.accessedAt < $1.accessedAt })
            where totalByteCount > maximumByteCount
        {
            try? fileManager.removeItem(at: entry.url)
            try? fileManager.removeItem(at: metadataURL(for: entry.key))
            totalByteCount -= entry.size
        }
    }

    private func bifURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("bif")
    }

    private func metadataURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key).appendingPathExtension("json")
    }
}
