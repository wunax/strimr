import CryptoKit
import ImageIO
import SwiftUI
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Keeps a small, last-known avatar per profile so cold launches never depend on a network image request.
@MainActor
final class ProfileAvatarCache {
    static let shared = ProfileAvatarCache()

    private struct Record: Codable {
        let source: URL
        let updatedAt: Date
        let data: Data
    }

    private var records: [String: Record] = [:]
    private var images: [String: Image] = [:]
    private var loaded: Set<String> = []
    private var requests: [String: Task<Image?, Never>] = [:]
    private var requestedURLs: [String: URL] = [:]
    private let directory = URL.cachesDirectory.appendingPathComponent("ProfileAvatars-v2", isDirectory: true)

    private init() {
        // Older chooser entries used raw user UUIDs that profile deletion could not identify.
        let legacyDirectory = URL.cachesDirectory.appendingPathComponent("ProfileAvatars", isDirectory: true)
        try? FileManager.default.removeItem(at: legacyDirectory)
    }

    func image(for profileID: String) -> Image? {
        if loaded.insert(profileID).inserted,
           let data = try? Data(contentsOf: fileURL(for: profileID)),
           let record = try? PropertyListDecoder().decode(Record.self, from: data),
           let image = Self.decode(record.data)
        {
            records[profileID] = record
            images[profileID] = image
        }
        return images[profileID]
    }

    func refresh(profileID: String, url: URL?) async -> Image? {
        let cached = image(for: profileID)
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return cached }
        if let record = records[profileID], record.source == url,
           Date().timeIntervalSince(record.updatedAt) < 6 * 60 * 60
        {
            return cached
        }
        let key = profileID + "|" + url.absoluteString
        requestedURLs[profileID] = url
        if let request = requests[key] {
            return await request.value
        }
        let request = Task<Image?, Never> {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard requestedURLs[profileID] == url else { return images[profileID] }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      data.count <= 5 * 1024 * 1024
                else { return cached }
                let thumbnail = await Task.detached(priority: .utility) { Self.thumbnail(data) }.value
                try Task.checkCancellation()
                guard requestedURLs[profileID] == url else { return images[profileID] }
                guard let thumbnail, let image = Self.decode(thumbnail) else { return cached }
                let record = Record(source: url, updatedAt: Date(), data: thumbnail)
                records[profileID] = record
                images[profileID] = image
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let encoded = try? PropertyListEncoder().encode(record) {
                    try? encoded.write(to: fileURL(for: profileID), options: .atomic)
                }
                return image
            } catch {
                return cached
            }
        }
        requests[key] = request
        let result = await request.value
        requests[key] = nil
        return result
    }

    func remove(profileID: String) {
        records[profileID] = nil
        images[profileID] = nil
        loaded.remove(profileID)
        requestedURLs[profileID] = nil
        for key in requests.keys.filter({ $0.hasPrefix(profileID + "|") }) {
            requests.removeValue(forKey: key)?.cancel()
        }
        try? FileManager.default.removeItem(at: fileURL(for: profileID))
    }

    private func fileURL(for profileID: String) -> URL {
        let key = SHA256.hash(data: Data(profileID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("plist")
    }

    private nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 384,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return nil }
        #if os(macOS)
            return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        #else
            return UIImage(cgImage: image).jpegData(compressionQuality: 0.9)
        #endif
    }

    private static func decode(_ data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}

struct CachedProfileAvatar<Placeholder: View>: View {
    let profileID: String
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: Image?

    init(profileID: String, url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.profileID = profileID
        self.url = url
        self.placeholder = placeholder
        _image = State(initialValue: ProfileAvatarCache.shared.image(for: profileID))
    }

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: profileID + "|" + (url?.absoluteString ?? "")) {
            image = ProfileAvatarCache.shared.image(for: profileID)
            let refreshed = await ProfileAvatarCache.shared.refresh(profileID: profileID, url: url)
            guard !Task.isCancelled else { return }
            image = refreshed
        }
    }
}
