// @copyright André Trettin

#if !os(macOS)
import UIKit
import CoreGraphics

extension UIImage {
    public func removeWhiteBackground() -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4 // 4 bytes per pixel (RGBA)
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue // ARGB

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixelBuffer = data.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4 // ARGB
                let alpha = pixelBuffer[offset + 0]
                let red = pixelBuffer[offset + 1]
                let green = pixelBuffer[offset + 2]
                let blue = pixelBuffer[offset + 3]

                // Check if the pixel is close to white (you can adjust the threshold)
                if red > 254 && green > 254 && blue > 254 && alpha > 200 {
                    // set clear color
                    pixelBuffer[offset + 0] = 0
                    pixelBuffer[offset + 1] = 0
                    pixelBuffer[offset + 2] = 0
                    pixelBuffer[offset + 3] = 0
                }
            }
        }

        guard let outputCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCGImage)
    }
}

#endif
