import CoreGraphics
import Foundation
import ImageIO
@testable import Strimr
import Testing
import UniformTypeIdentifiers

struct ArtworkUploadTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil,
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixelSize(of data: Data) throws -> (width: Int, height: Int, type: String) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return try (
            #require(properties[kCGImagePropertyPixelWidth] as? Int),
            #require(properties[kCGImagePropertyPixelHeight] as? Int),
            #require(CGImageSourceGetType(source) as String?),
        )
    }

    @Test func `large images are scaled down and sent as JPEG`() async throws {
        let upload = try #require(await ArtworkUpload.prepare(pngData(width: 6000, height: 3000), for: .background))
        let size = try pixelSize(of: upload.data)

        #expect(upload.contentType == "image/jpeg")
        #expect(size.type == UTType.jpeg.identifier)
        #expect(size.width == ArtworkUpload.maxPixelSize)
        #expect(size.height == 2000)
    }

    @Test func `small images keep their size`() async throws {
        let upload = try #require(await ArtworkUpload.prepare(pngData(width: 400, height: 600), for: .poster))
        let size = try pixelSize(of: upload.data)

        #expect(size.width == 400)
        #expect(size.height == 600)
    }

    @Test func `logos stay PNG to keep their transparency`() async throws {
        let upload = try #require(await ArtworkUpload.prepare(pngData(width: 800, height: 300), for: .logo))

        #expect(upload.contentType == "image/png")
        #expect(try pixelSize(of: upload.data).type == UTType.png.identifier)
    }

    @Test func `data that is not an image is refused`() async {
        #expect(await ArtworkUpload.prepare(Data("not an image".utf8), for: .poster) == nil)
    }
}
