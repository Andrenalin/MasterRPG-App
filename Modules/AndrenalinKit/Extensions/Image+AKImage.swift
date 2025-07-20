// @copyright André Trettin

import SwiftUI

#if os(macOS)
import AppKit

public typealias AKImage = NSImage

//extension NSImage: @unchecked @retroactive Sendable {}

public extension Image {
    init(akImage: AKImage) {
        self.init(nsImage: akImage)
    }
}

public extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation else { return nil }
        guard let imageRep = NSBitmapImageRep(data: tiff) else { return nil }
        
        let options: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: compressionQuality,
        ]
        
        return imageRep.representation(using: .jpeg, properties: options)
    }
}

public extension AKImage {
    func resize(to targetSize: CGSize, topAligned: Bool = false) -> AKImage? {
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        var sourceRect: CGRect = .zero
        if topAligned {
            if widthRatio > heightRatio {
                let originSrc = CGPoint(x: 0, y: size.height - size.width)
                let sizeSrc = CGSize(width: size.width, height: size.width)
                sourceRect = CGRect(origin: originSrc, size: sizeSrc)
            } else {
                let diff = (size.width - size.height)
                var x = 0.0
                if diff > 1.0 {
                    x = diff / 2.0
                }
                let originSrc = CGPoint(x: x, y: 0.0)
                let sizeSrc = CGSize(width: size.height, height: size.height)
                sourceRect = CGRect(origin: originSrc, size: sizeSrc)
            }
        }
        
        let rect = CGRect(origin: .zero, size: targetSize)
        let newImage = NSImage(size: rect.size)
        newImage.lockFocus()
        let ctx = NSGraphicsContext.current
        ctx?.imageInterpolation = .high
        draw(in: rect, from: sourceRect, operation: .copy, fraction: 1)
        newImage.unlockFocus()
        
        return newImage
    }
    
    var fixedSize: CGSize {
        var width = size.width
        var height = size.height
        representations.forEach {
            width = max(width, CGFloat($0.pixelsWide))
            height = max(height, CGFloat($0.pixelsHigh))
        }
        return CGSize(width: width, height: height)
    }
    
    func resetSize() {
        size = fixedSize
    }
}

#else
import UIKit

public typealias AKImage = UIImage

public extension Image {
    init(akImage: AKImage) {
        self.init(uiImage: akImage)
    }
}

public extension AKImage {
    
    func resize(to targetSize: CGSize, topAligned: Bool = false) -> AKImage? {
        let pixelScale: CGFloat = 3.0

        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let minRatio = min(widthRatio, heightRatio)
        var sourceRect = CGRect(origin: .zero, size: targetSize * pixelScale)
        if topAligned {
            if widthRatio > heightRatio {
                let originSrc = CGPoint.zero
                let sizeSrc = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
                sourceRect = CGRect(origin: originSrc, size: sizeSrc * pixelScale)
            } else {
                let diff = (size.width - size.height)
                var x = 0.0
                if diff > 1.0 {
                    x = diff / 2.0
                }
                let originSrc = CGPoint(x: -x * minRatio, y: 0.0)
                let sizeSrc = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
                sourceRect = CGRect(origin: originSrc * pixelScale, size: sizeSrc * pixelScale)
            }
        }
        
        let rect = CGRect(origin: .zero, size: targetSize * pixelScale)
        
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        
        return renderer.image { _ in
            draw(in: sourceRect)
        }
    }
    
    var fixedSize: CGSize {
        size
    }
    
    func resetSize() {
        // nothing to do
    }
}

#endif
