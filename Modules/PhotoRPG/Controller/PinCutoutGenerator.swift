// @copyright André Trettin

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// The rules that decide whether a subject mask really separated a figure from its photo.
/// Pure, so they are testable without running Vision.
enum PinCutoutPolicy {
    /// Longest edge, in pixels, of the photo that is analysed and of the cutout that results.
    static let sourceMaxPixelSize: CGFloat = 768
    /// Bump when the generator output changes, so cached cutouts are made again.
    static let revision = 1
    /// A subject covering less than this is noise, not a figure.
    static let minimumCoverage = 0.05
    /// A subject covering more than this means nothing was separated from the background.
    static let maximumCoverage = 0.95

    static func isUsable(coverage: Double) -> Bool {
        (minimumCoverage...maximumCoverage).contains(coverage)
    }
}

/// Lifts the foreground subject of a photo into an image with a transparent background.
enum PinCutoutGenerator {
    private static let ciContext = CIContext()

    /// - Returns: the subject cropped to its extent with alpha, or `nil` when Vision finds no
    ///   usable subject (or is unavailable, e.g. in a simulator without the needed hardware).
    @concurrent
    static func cutout(from image: CGImage) async -> CGImage? {
        // The Vision API without the `VN` prefix exposes its mask buffer from iOS 27 only; the
        // deployment target is 26.
        do {
            let handler = VNImageRequestHandler(cgImage: image)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            if let labelCoverage = coverage(of: observation.instanceMask),
               !PinCutoutPolicy.isUsable(coverage: labelCoverage) {
                return nil
            }
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: masked)
            guard !ciImage.extent.isEmpty, !ciImage.extent.isInfinite else { return nil }
            return ciContext.createCGImage(
                ciImage,
                from: ciImage.extent,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        } catch {
            return nil
        }
    }

    /// The share of pixels that belong to any instance, for an 8-bit instance-label buffer
    /// (0 = background). `nil` for any other pixel format, which skips the coverage gate.
    static func coverage(of mask: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        guard width > 0, height > 0 else { return nil }
        var covered = 0
        for row in 0..<height {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width where pixels[column] != 0 {
                covered += 1
            }
        }
        return Double(covered) / Double(width * height)
    }
}
