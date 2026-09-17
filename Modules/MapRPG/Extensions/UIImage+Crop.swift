// @copyright André Trettin

import CoreRPG

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
}
#endif
