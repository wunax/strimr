import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

actor JellyfinTrickplayThumbnailProvider: ScrubThumbnailProviding {
    private let source: JellyfinTrickplaySource
    private let session: URLSession
    private let cacheDirectory: URL
    private var sheets: [Int: CGImage] = [:]
    private var sheetOrder: [Int] = []
    private var state: PlexBIFAvailability = .loading
    private var isCancelled = false

    init(source: JellyfinTrickplaySource, session: URLSession = .shared) {
        self.source = source
        self.session = session
        let digest = SHA256.hash(data: Data(source.cacheKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("StrimrTrickplay", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(digest, isDirectory: true)
    }

    func prepare() async {
        guard !isCancelled, source.thumbnailCount > 0 else {
            state = .unavailable
            return
        }
        do {
            _ = try await sheet(index: 0)
            state = .ready
        } catch {
            guard !Task.isCancelled, !isCancelled else { return }
            state = .temporarilyFailed
        }
    }

    func availability() -> PlexBIFAvailability {
        state
    }

    func thumbnail(at seconds: Double) async -> PlexBIFThumbnail? {
        guard !isCancelled,
              seconds.isFinite,
              source.intervalMilliseconds > 0,
              source.tileColumns > 0,
              source.tileRows > 0
        else { return nil }

        let requested = max(0, Int(seconds * 1000) / source.intervalMilliseconds)
        let frameIndex = min(requested, max(0, source.thumbnailCount - 1))
        let framesPerSheet = source.tileColumns * source.tileRows
        let sheetIndex = frameIndex / framesPerSheet
        let tileIndex = frameIndex % framesPerSheet

        do {
            let image = try await sheet(index: sheetIndex)
            let column = tileIndex % source.tileColumns
            let row = tileIndex / source.tileColumns
            let crop = CGRect(
                x: column * source.width,
                y: image.height - ((row + 1) * source.height),
                width: source.width,
                height: source.height
            )
            guard let thumbnail = image.cropping(to: crop) else { return nil }
            return PlexBIFThumbnail(
                bucketPosition: Double(frameIndex * source.intervalMilliseconds) / 1000,
                image: thumbnail
            )
        } catch {
            guard !Task.isCancelled, !isCancelled else { return nil }
            state = .temporarilyFailed
            return nil
        }
    }

    func cancel() {
        isCancelled = true
        sheets.removeAll()
        sheetOrder.removeAll()
    }

    private func sheet(index: Int) async throws -> CGImage {
        if let cached = sheets[index] { return cached }
        let fileURL = cacheDirectory.appendingPathComponent("\(index).jpg")
        let data: Data
        if let cached = try? Data(contentsOf: fileURL), !cached.isEmpty {
            data = cached
        } else {
            guard let url = source.sheetURL(index: index) else {
                throw JellyfinAPIError.invalidResponse
            }
            var request = URLRequest(url: url)
            source.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (downloaded, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  200 ..< 300 ~= response.statusCode,
                  !downloaded.isEmpty
            else { throw JellyfinAPIError.invalidResponse }
            data = downloaded
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw JellyfinAPIError.invalidResponse }
        sheets[index] = image
        sheetOrder.removeAll { $0 == index }
        sheetOrder.append(index)
        while sheetOrder.count > 4 {
            sheets[sheetOrder.removeFirst()] = nil
        }
        return image
    }
}
