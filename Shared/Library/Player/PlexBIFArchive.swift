import CoreGraphics
import Foundation
import ImageIO

nonisolated enum PlexBIFArchiveError: Error, LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case truncated
    case invalidMagic
    case unsupportedVersion(UInt32)
    case invalidImageCount
    case invalidIndex
    case invalidJPEG

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "Plex preview index exceeds the supported size."
        case .truncated:
            "Plex preview index is truncated."
        case .invalidMagic:
            "Plex preview index has an invalid signature."
        case let .unsupportedVersion(version):
            "Plex preview index version \(version) is unsupported."
        case .invalidImageCount:
            "Plex preview index has an invalid image count."
        case .invalidIndex:
            "Plex preview index is malformed."
        case .invalidJPEG:
            "Plex preview image could not be decoded."
        }
    }
}

nonisolated struct PlexBIFArchive: Sendable {
    static let maximumFileSize = 100 * 1024 * 1024
    private static let headerSize = 64
    private static let indexEntrySize = 8
    private static let magic = Data([0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A])

    struct Frame: Sendable {
        let timestampMilliseconds: UInt64
        let offset: UInt64
        let length: UInt64
    }

    let fileURL: URL
    let frames: [Frame]

    nonisolated init(fileURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSizeNumber = attributes[.size] as? NSNumber else {
            throw PlexBIFArchiveError.truncated
        }
        let fileSize = fileSizeNumber.uint64Value
        guard fileSize <= UInt64(Self.maximumFileSize) else {
            throw PlexBIFArchiveError.fileTooLarge
        }
        guard fileSize >= UInt64(Self.headerSize + Self.indexEntrySize * 2) else {
            throw PlexBIFArchiveError.truncated
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let header = try Self.read(
            handle: handle,
            offset: 0,
            count: Self.headerSize,
        )
        guard header.prefix(Self.magic.count) == Self.magic else {
            throw PlexBIFArchiveError.invalidMagic
        }

        let version = Self.uint32(in: header, at: 8)
        guard version == 0 else {
            throw PlexBIFArchiveError.unsupportedVersion(version)
        }
        let imageCount = UInt64(Self.uint32(in: header, at: 12))
        guard imageCount > 0 else {
            throw PlexBIFArchiveError.invalidImageCount
        }
        let multiplierValue = Self.uint32(in: header, at: 16)
        let multiplier = UInt64(multiplierValue == 0 ? 1000 : multiplierValue)

        let entryCount = imageCount + 1
        guard entryCount <= (UInt64(Self.maximumFileSize) - UInt64(Self.headerSize))
            / UInt64(Self.indexEntrySize)
        else {
            throw PlexBIFArchiveError.invalidImageCount
        }
        let indexByteCount = entryCount * UInt64(Self.indexEntrySize)
        let dataStart = UInt64(Self.headerSize) + indexByteCount
        guard dataStart <= fileSize, indexByteCount <= UInt64(Int.max) else {
            throw PlexBIFArchiveError.truncated
        }

        let indexData = try Self.read(
            handle: handle,
            offset: UInt64(Self.headerSize),
            count: Int(indexByteCount),
        )
        var rawEntries: [(timestamp: UInt32, offset: UInt64)] = []
        rawEntries.reserveCapacity(Int(entryCount))
        for entryIndex in 0 ..< Int(entryCount) {
            let byteOffset = entryIndex * Self.indexEntrySize
            rawEntries.append((
                timestamp: Self.uint32(in: indexData, at: byteOffset),
                offset: UInt64(Self.uint32(in: indexData, at: byteOffset + 4)),
            ))
        }

        guard rawEntries.last?.timestamp == UInt32.max,
              rawEntries.last?.offset == fileSize
        else {
            throw PlexBIFArchiveError.invalidIndex
        }

        var parsedFrames: [Frame] = []
        parsedFrames.reserveCapacity(Int(imageCount))
        var previousTimestamp: UInt32?
        for frameIndex in 0 ..< Int(imageCount) {
            let current = rawEntries[frameIndex]
            let next = rawEntries[frameIndex + 1]
            guard current.offset >= dataStart,
                  next.offset > current.offset,
                  next.offset <= fileSize
            else {
                throw PlexBIFArchiveError.invalidIndex
            }
            if let previousTimestamp, current.timestamp <= previousTimestamp {
                throw PlexBIFArchiveError.invalidIndex
            }
            previousTimestamp = current.timestamp

            let timestamp = UInt64(current.timestamp)
            guard timestamp <= UInt64.max / multiplier else {
                throw PlexBIFArchiveError.invalidIndex
            }
            parsedFrames.append(Frame(
                timestampMilliseconds: timestamp * multiplier,
                offset: current.offset,
                length: next.offset - current.offset,
            ))
        }

        self.fileURL = fileURL
        frames = parsedFrames
    }

    nonisolated func frameIndex(at seconds: Double) -> Int {
        guard frames.count > 1, seconds.isFinite else { return 0 }
        let boundedSeconds = min(
            max(0, seconds),
            Double(UInt64.max) / 1000,
        )
        let targetMilliseconds = UInt64(boundedSeconds * 1000)
        var lower = 0
        var upper = frames.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if frames[middle].timestampMilliseconds <= targetMilliseconds {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return min(max(lower - 1, 0), frames.count - 1)
    }

    nonisolated func bucketPosition(at seconds: Double) -> Double {
        Double(frames[frameIndex(at: seconds)].timestampMilliseconds) / 1000
    }

    nonisolated func thumbnail(at seconds: Double) throws -> ScrubThumbnail {
        try thumbnail(frameIndex: frameIndex(at: seconds))
    }

    nonisolated func thumbnail(frameIndex: Int) throws -> ScrubThumbnail {
        guard frames.indices.contains(frameIndex) else {
            throw PlexBIFArchiveError.invalidIndex
        }
        let frame = frames[frameIndex]
        guard frame.length <= UInt64(Int.max) else {
            throw PlexBIFArchiveError.invalidIndex
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try Self.read(
            handle: handle,
            offset: frame.offset,
            count: Int(frame.length),
        )
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw PlexBIFArchiveError.invalidJPEG
        }
        return ScrubThumbnail(
            bucketPosition: Double(frame.timestampMilliseconds) / 1000,
            image: image,
        )
    }

    private nonisolated static func read(
        handle: FileHandle,
        offset: UInt64,
        count: Int,
    ) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw PlexBIFArchiveError.truncated
        }
        return data
    }

    private nonisolated static func uint32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
