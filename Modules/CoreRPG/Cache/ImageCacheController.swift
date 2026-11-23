// @copyright André Trettin


#if os(macOS)
import AppKit
#else
import UIKit
#endif

import Foundation

public struct ImageCacheController: Sendable {
    public init() {}
    
    private let cache = ObjectCache<AKImage>()
    
    public func hasObject(for itemId: UUID) async -> Bool {
        await cache.hasObject(for: itemId)
    }
    
    public func object(for itemId: UUID) async -> AKImage? {
        await cache.cachedObject(for: itemId)
    }
    
    public func removeObject(for itemId: UUID) async {
        await cache.removeObject(for: itemId)
        await cache.removeFromDisk(for: itemId)
    }
    
    public func setObject(_ object: AKImage, for itemId: UUID) async {
        await cache.insertObject(object, for: itemId, cost: Self.bitmapCost(of: object))
    }

    /// Four bytes per pixel. `size` is in points, which undercounts a 3× image nine times
    /// over. See CODE_AUDIT_23 §7.6.
    static func bitmapCost(of image: AKImage) -> Int {
        #if os(macOS)
        let pixelWidth = image.representations.map(\.pixelsWide).max() ?? 0
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? 0
        let pixels = pixelWidth > 0 && pixelHeight > 0
            ? Double(pixelWidth) * Double(pixelHeight)
            : image.size.width * image.size.height
        #else
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        #endif
        guard pixels.isFinite, pixels > 0 else { return 0 }
        return Int(min(pixels * 4, Double(Int32.max)))
    }
    
    public func loadFromDisk(for itemId: UUID) async -> AKImage? {
        await cache.loadImageFromDisk(for: itemId)
    }

    public func saveToDisk(_ object: AKImage, for itemId: UUID) async {
        await cache.saveImageToDisk(object, for: itemId)
    }
}
