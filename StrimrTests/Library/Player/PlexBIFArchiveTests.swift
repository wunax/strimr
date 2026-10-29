import CoreGraphics
import Foundation
import ImageIO
@testable import Strimr
import Testing
import UniformTypeIdentifiers

struct PlexBIFArchiveTests {
    @Test func `frames take their timestamps from the index and the multiplier`() throws {
        let file = try BIFFile(timestamps: [0, 10, 20], multiplier: 500)

        let archive = try PlexBIFArchive(fileURL: file.url)

        #expect(archive.frames.map(\.timestampMilliseconds) == [0, 5000, 10000])
    }

    @Test func `a zero multiplier means one second per unit`() throws {
        let file = try BIFFile(timestamps: [0, 10], multiplier: 0)

        let archive = try PlexBIFArchive(fileURL: file.url)

        #expect(archive.frames.map(\.timestampMilliseconds) == [0, 10000])
    }

    @Test(arguments: [
        (-5.0, 0), (0.0, 0), (9.9, 0), (10.0, 1), (25.0, 2), (10000.0, 2), (Double.nan, 0), (Double.infinity, 0),
    ])
    func `a time maps to the last frame that started before it`(seconds: Double, expected: Int) throws {
        let file = try BIFFile(timestamps: [0, 10, 20])
        let archive = try PlexBIFArchive(fileURL: file.url)

        #expect(archive.frameIndex(at: seconds) == expected)
    }

    @Test func `the bucket position is the start of the frame`() throws {
        let file = try BIFFile(timestamps: [0, 10, 20])
        let archive = try PlexBIFArchive(fileURL: file.url)

        #expect(archive.bucketPosition(at: 14) == 10)
    }

    @Test func `a frame decodes to its image`() throws {
        let file = try BIFFile(timestamps: [0, 10])
        let archive = try PlexBIFArchive(fileURL: file.url)

        let thumbnail = try archive.thumbnail(at: 12)

        #expect(thumbnail.bucketPosition == 10)
        #expect(thumbnail.image.width == 4)
    }

    @Test func `a frame outside the archive is rejected`() throws {
        let file = try BIFFile(timestamps: [0, 10])
        let archive = try PlexBIFArchive(fileURL: file.url)

        #expect(throws: PlexBIFArchiveError.invalidIndex) {
            try archive.thumbnail(frameIndex: 5)
        }
    }

    @Test func `a frame that is not a JPEG is rejected`() throws {
        let file = try BIFFile(timestamps: [0], images: [Data(repeating: 0xAB, count: 16)])
        let archive = try PlexBIFArchive(fileURL: file.url)

        #expect(throws: PlexBIFArchiveError.invalidJPEG) {
            try archive.thumbnail(frameIndex: 0)
        }
    }

    @Test func `a wrong signature is rejected`() throws {
        var data = try BIFFile.archiveData(timestamps: [0])
        data[1] = 0x00
        let file = try BIFFile(data: data)

        #expect(throws: PlexBIFArchiveError.invalidMagic) {
            try PlexBIFArchive(fileURL: file.url)
        }
    }

    @Test func `an unknown version is rejected`() throws {
        var data = try BIFFile.archiveData(timestamps: [0])
        data[8] = 2
        let file = try BIFFile(data: data)

        #expect(throws: PlexBIFArchiveError.unsupportedVersion(2)) {
            try PlexBIFArchive(fileURL: file.url)
        }
    }

    @Test func `an archive without images is rejected`() throws {
        var data = try BIFFile.archiveData(timestamps: [0])
        data.replaceSubrange(12 ..< 16, with: BIFFile.uint32(0))
        let file = try BIFFile(data: data)

        #expect(throws: PlexBIFArchiveError.invalidImageCount) {
            try PlexBIFArchive(fileURL: file.url)
        }
    }

    @Test func `a cut off file is rejected`() throws {
        let data = try BIFFile.archiveData(timestamps: [0, 10])
        let file = try BIFFile(data: data.prefix(data.count - 10))

        #expect(throws: PlexBIFArchiveError.invalidIndex) {
            try PlexBIFArchive(fileURL: file.url)
        }
    }

    @Test func `a file shorter than its header is rejected`() throws {
        let file = try BIFFile(data: Data(repeating: 0, count: 20))

        #expect(throws: PlexBIFArchiveError.truncated) {
            try PlexBIFArchive(fileURL: file.url)
        }
    }

    @Test func `timestamps that go back are rejected`() throws {
        let file = try BIFFile(timestamps: [10, 5])

        #expect(throws: PlexBIFArchiveError.invalidIndex) {
            try PlexBIFArchive(fileURL: file.url)
        }
    }
}

/// A BIF archive written to a temporary file: 64-byte header, then an index of (timestamp, offset) pairs ending
/// with (0xFFFFFFFF, file size), then the JPEG frames.
private final class BIFFile {
    let url: URL

    init(data: Data) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("strimr.tests.\(UUID().uuidString).bif")
        try data.write(to: url)
    }

    convenience init(timestamps: [UInt32], multiplier: UInt32 = 1000, images: [Data]? = nil) throws {
        try self.init(data: Self.archiveData(timestamps: timestamps, multiplier: multiplier, images: images))
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    static func archiveData(timestamps: [UInt32], multiplier: UInt32 = 1000, images: [Data]? = nil) throws -> Data {
        let images = try images ?? timestamps.map { _ in try jpeg() }
        var header = Data([0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A])
        header += uint32(0)
        header += uint32(UInt32(timestamps.count))
        header += uint32(multiplier)
        header += Data(repeating: 0, count: 64 - header.count)

        let dataStart = 64 + (timestamps.count + 1) * 8
        var index = Data()
        var offset = dataStart
        for (timestamp, image) in zip(timestamps, images) {
            index += uint32(timestamp) + uint32(UInt32(offset))
            offset += image.count
        }
        index += uint32(.max) + uint32(UInt32(offset))
        return images.reduce(header + index, +)
    }

    static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func jpeg() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil),
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
