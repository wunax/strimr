import CoreImage.CIFilterBuiltins
import SwiftUI

enum QRCodeImage {
    private static let context = CIContext()

    static func make(_ string: String) -> Image? {
        guard let data = string.data(using: .ascii) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let image = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}
