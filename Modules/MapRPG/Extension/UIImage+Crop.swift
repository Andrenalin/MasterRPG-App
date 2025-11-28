// @copyright André Trettin

import AndrenalinKit

#if os(macOS)
import AppKit

extension AKImage {
    func cropping(to rect: CGRect) -> AKImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let imageRef = cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { return nil }
        guard let cgImage = imageRef.cropping(to: rect) else { return nil }
        return AKImage(cgImage: cgImage, size: rect.size)
    }
}

#else
import UIKit

extension AKImage {
    func cropping(to rect: CGRect) -> AKImage? {
        guard let cgImage = cgImage?.cropping(to: rect) else {
            return nil
        }
        return AKImage(cgImage: cgImage)
    }

    func crop(in rect: CGRect) -> AKImage? {
        guard let cgImage else {
            return nil
        }
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
        let context = UIGraphicsGetCurrentContext()

        context?.translateBy(x: 0.0, y: size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height), byTiling: false)
        context?.clip(to: [rect])

        let croppedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return croppedImage
    }
}
#endif
