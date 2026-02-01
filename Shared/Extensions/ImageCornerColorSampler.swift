import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

enum ImageCornerColorSampler {
    static func colors(from data: Data) -> [Color] {
        #if canImport(UIKit)
            guard let image = UIImage(data: data) else { return [] }
            return colors(from: image)
        #else
            return []
        #endif
    }

    #if canImport(UIKit)
        static func colors(from image: UIImage) -> [Color] {
            guard let cgImage = image.cgImage else { return [] }

            let width = 4
            let height = 4
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

            guard let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return []
            }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            func colorAt(x: Int, y: Int) -> Color {
                let offset = (y * width + x) * bytesPerPixel
                let red = Double(pixelData[offset]) / 255.0
                let green = Double(pixelData[offset + 1]) / 255.0
                let blue = Double(pixelData[offset + 2]) / 255.0
                let alpha = Double(pixelData[offset + 3]) / 255.0
                return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
            }

            let topLeft = colorAt(x: 0, y: height - 1)
            let topRight = colorAt(x: width - 1, y: height - 1)
            let bottomRight = colorAt(x: width - 1, y: 0)
            let bottomLeft = colorAt(x: 0, y: 0)

            return [topLeft, topRight, bottomRight, bottomLeft]
        }
    #endif
}
