// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import CoreRPG

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The full-image byte budget the module caches share. See CODE_AUDIT_29 §7.3.
@MainActor
@Suite("Image memory budget")
struct ImageMemoryBudgetTests {
    private static func image(side: Int = 16) -> AKImage {
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let cgImage = context.makeImage()!
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: CGSize(width: side, height: side))
        #else
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        #endif
    }

    @Test("Over the shared budget the least recently used image of any cache leaves first")
    func crossCacheEviction() throws {
        let image = Self.image()
        let cost = ImageCacheController.bitmapCost(of: image)
        try #require(cost > 0)
        // Room for two images, not three.
        let budget = ImageMemoryBudget(byteLimit: cost * 2 + cost / 2)
        let photos = ObservableImageCache(budget: budget)
        let maps = ObservableImageCache(budget: budget)
        let first = UUID(), second = UUID(), third = UUID()

        photos.setImage(image, for: first)
        maps.setImage(image, for: second)
        #expect(budget.cachedBytes == cost * 2)

        photos.setImage(image, for: third)
        // The oldest image overall (`first`, of the same cache) left, the other cache's stayed.
        #expect(photos.image(for: first) == nil)
        #expect(maps.image(for: second) != nil)
        #expect(photos.image(for: third) != nil)

        maps.setImage(image, for: first)
        // Now `second` (maps) is the oldest of all and leaves, `third` (photos) stays.
        #expect(maps.image(for: second) == nil)
        #expect(photos.image(for: third) != nil)
        #expect(budget.cachedBytes <= budget.byteLimit)
    }

    @Test("A single image over the budget is kept")
    func singleOversizedImageKept() {
        let image = Self.image()
        let budget = ImageMemoryBudget(byteLimit: 1)
        let cache = ObservableImageCache(budget: budget)
        let itemId = UUID()
        cache.setImage(image, for: itemId)
        #expect(cache.image(for: itemId) != nil)
    }

    @Test("Trimming drops the full images but keeps the thumbnails")
    func trimKeepsThumbnails() {
        let image = Self.image()
        let cache = ObservableImageCache(imageByteLimit: .max)
        let itemId = UUID()
        cache.setImage(image, for: itemId)
        cache.setThumbnail(image, for: itemId)
        cache.trimImages()
        #expect(cache.image(for: itemId) == nil)
        #expect(cache.thumbnail(for: itemId) != nil)
        #expect(cache.cachedImageBytes == 0)
    }
}
#endif
