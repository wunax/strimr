import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image ready to be sent to the server as artwork.
nonisolated struct ArtworkUpload: Equatable {
    static let maxPixelSize = 4000

    let data: Data
    let contentType: String

    /// Scales the image down to `maxPixelSize` and encodes it as JPEG, or as PNG for a logo, whose transparency
    /// JPEG would lose. nil when the data is not an image.
    @concurrent
    nonisolated static func prepare(_ data: Data, for kind: EditableArtworkKind) async -> ArtworkUpload? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }

        let type: UTType = kind == .logo ? .png : .jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ArtworkUpload(data: output as Data, contentType: type.preferredMIMEType ?? "image/jpeg")
    }
}
