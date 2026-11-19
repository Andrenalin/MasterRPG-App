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

/// CODE_AUDIT_TestGaps §7.2: the image caches decide the memory use of every image-heavy module.
/// Covered here: the memory cache and its disk fallback (`ObjectCache`), the bounded LRU that
/// SwiftUI views read (`ObservableImageCache`) and the thumbnail pipeline every module's
/// `CacheController` shares (`ImageCacheControllable`). The disk cache lives in the real caches
/// folder under the item's id, so each test uses fresh ids and removes its files.
@Suite("Image caches")
struct ImageCacheTests {
    private static func image(side: Int = 8) -> AKImage {
        let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let cgImage = context.makeImage()!
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: CGSize(width: side, height: side))
        #else
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        #endif
    }

    // MARK: - ObjectCache memory

    @Test("An inserted object is found by its id, and a missing one is not")
    func memoryHitAndMiss() async {
        let cache = ObjectCache<AKImage>()
        let id = UUID()
        let image = Self.image()

        #expect(await cache.cachedObject(for: id) == nil)
        #expect(await !cache.hasObject(for: id))
        await cache.insertObject(image, for: id, cost: 256)

        #expect(await cache.cachedObject(for: id) === image)
        #expect(await cache.hasObject(for: id))
        #expect(await cache.cachedObject(for: UUID()) == nil)
    }

    @Test("Inserting nil removes the object, and removing an unknown id is harmless")
    func nilInsertRemoves() async {
        let cache = ObjectCache<AKImage>()
        let id = UUID()
        await cache.insertObject(Self.image(), for: id, cost: 256)

        await cache.insertObject(nil, for: id, cost: 0)
        await cache.removeObject(for: UUID())

        #expect(await !cache.hasObject(for: id))
    }

    @Test("Inserting again replaces the object of that id")
    func insertReplaces() async {
        let cache = ObjectCache<AKImage>()
        let id = UUID()
        let second = Self.image(side: 16)
        await cache.insertObject(Self.image(), for: id, cost: 256)

        await cache.insertObject(second, for: id, cost: 1_024)

        #expect(await cache.cachedObject(for: id) === second)
    }

    @Test("A cache over its count limit evicts instead of growing")
    func countLimitEvicts() async {
        // `NSCache` documents its limits as not strict, so only the existence of eviction is
        // asserted, not which entries remain.
        let cache = ObjectCache<AKImage>(countLimit: 5)
        let ids = (0..<60).map { _ in UUID() }
        for id in ids {
            await cache.insertObject(Self.image(), for: id, cost: 256)
        }

        var retained = 0
        for id in ids where await cache.hasObject(for: id) {
            retained += 1
        }

        #expect(retained < ids.count, "nothing was evicted at a limit of 5 for 60 inserts")
        #expect(retained > 0)
    }

    // MARK: - ObjectCache disk

    @Test("An image saved to disk is loaded again and removed from disk")
    func diskRoundTrip() async {
        let cache = ObjectCache<AKImage>()
        let id = UUID()
        defer { Task { await cache.removeFromDisk(for: id) } }

        #expect(await cache.loadImageFromDisk(for: id) == nil)
        await cache.saveImageToDisk(Self.image(side: 12), for: id)
        let loaded = await cache.loadImageFromDisk(for: id)

        #expect(loaded != nil)
        #expect(loaded?.size.width == 12)
        #expect(loaded?.size.height == 12)

        await cache.removeFromDisk(for: id)
        #expect(await cache.loadImageFromDisk(for: id) == nil)
        // Removing again, and removing an id that was never saved, is harmless.
        await cache.removeFromDisk(for: id)
        await cache.removeFromDisk(for: UUID())
    }

    @Test("The disk copy survives the memory cache and a new cache instance")
    func diskOutlivesMemory() async {
        let id = UUID()
        let writer = ObjectCache<AKImage>()
        defer { Task { await writer.removeFromDisk(for: id) } }
        await writer.insertObject(Self.image(), for: id, cost: 256)
        await writer.saveImageToDisk(Self.image(), for: id)
        await writer.removeObject(for: id)

        let reader = ObjectCache<AKImage>()

        #expect(await reader.cachedObject(for: id) == nil)
        #expect(await reader.loadImageFromDisk(for: id) != nil)
    }

    @Test("Different ids that share the two-character subfolder do not overwrite each other")
    func sameSubfolderDifferentFiles() async throws {
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000AB"))
        let second = try #require(UUID(uuidString: "11111111-1111-1111-1111-1111111111AB"))
        let cache = ObjectCache<AKImage>()
        defer { Task { await cache.removeFromDisk(for: first); await cache.removeFromDisk(for: second) } }

        await cache.saveImageToDisk(Self.image(side: 8), for: first)
        await cache.saveImageToDisk(Self.image(side: 20), for: second)

        #expect(await cache.loadImageFromDisk(for: first)?.size.width == 8)
        #expect(await cache.loadImageFromDisk(for: second)?.size.width == 20)
    }

    @Test("A damaged cache file is a miss, not a crash")
    func damagedFileIsAMiss() async throws {
        let id = UUID()
        let cache = ObjectCache<AKImage>()
        await cache.saveImageToDisk(Self.image(), for: id)
        defer { Task { await cache.removeFromDisk(for: id) } }
        let file = URL.cachesDirectory
            .appending(path: "ImageCache", directoryHint: .isDirectory)
            .appending(path: String(id.uuidString.suffix(2)))
            .appending(path: id.uuidString)
            .appendingPathExtension("jpg")
        try Data("not an image".utf8).write(to: file)

        #expect(await cache.loadImageFromDisk(for: id) == nil)
    }

    // MARK: - ObservableImageCache

    @Test("The observable image cache keeps the 120 most recently used full images")
    @MainActor
    func observableImageEvictsLeastRecentlyUsed() {
        let cache = ObservableImageCache()
        let ids = (0..<121).map { _ in UUID() }

        for id in ids { cache.setImage(Self.image(side: 2), for: id) }

        #expect(cache.image(for: ids[0]) == nil, "the oldest image is evicted at the 121st")
        #expect(cache.image(for: ids[1]) != nil)
        #expect(cache.image(for: ids[120]) != nil)
    }

    @Test("Reading by setting again keeps an image from being the next to leave")
    @MainActor
    func observableImageTouchProtects() {
        let cache = ObservableImageCache()
        let ids = (0..<120).map { _ in UUID() }
        for id in ids { cache.setImage(Self.image(side: 2), for: id) }

        cache.setImage(Self.image(side: 2), for: ids[0])
        cache.setImage(Self.image(side: 2), for: UUID())

        #expect(cache.image(for: ids[0]) != nil, "the touched image was most recently used")
        #expect(cache.image(for: ids[1]) == nil, "the least recently used one left instead")
    }

    @Test("The observable cache keeps 400 thumbnails, separately from the images")
    @MainActor
    func observableThumbnailsHaveTheirOwnLimit() {
        let cache = ObservableImageCache()
        let ids = (0..<401).map { _ in UUID() }
        let keptImage = UUID()
        cache.setImage(Self.image(side: 2), for: keptImage)

        for id in ids { cache.setThumbnail(Self.image(side: 2), for: id) }

        #expect(cache.thumbnail(for: ids[0]) == nil)
        #expect(cache.thumbnail(for: ids[400]) != nil)
        #expect(cache.image(for: keptImage) != nil, "thumbnails never evict full images")
    }

    @Test("Setting nil and resetting remove entries; reset can keep the full image")
    @MainActor
    func observableRemoval() {
        let cache = ObservableImageCache()
        let id = UUID()
        cache.setImage(Self.image(side: 2), for: id)
        cache.setThumbnail(Self.image(side: 2), for: id)

        cache.reset(for: id, includeImage: false)
        #expect(cache.image(for: id) != nil)
        #expect(cache.thumbnail(for: id) == nil)

        cache.setThumbnail(Self.image(side: 2), for: id)
        cache.setImage(nil, for: id)
        #expect(cache.image(for: id) == nil)
        #expect(cache.thumbnail(for: id) != nil)

        cache.reset(for: id)
        #expect(cache.thumbnail(for: id) == nil)
    }

    // MARK: - ImageCacheControllable

    /// A conformer whose thumbnail is made in memory and counted.
    private final class CountingBox: @unchecked Sendable {
        private let lock = NSLock()
        private var created = 0
        func increment() { lock.withLock { created += 1 } }
        var count: Int { lock.withLock { created } }
    }

    private struct ProbeCacheController: ImageCacheControllable {
        @MainActor init(box: CountingBox) {
            self.box = box
            cacheStorage = ImageCacheControllableStorage()
        }

        let box: CountingBox
        let cacheStorage: ImageCacheControllableStorage

        @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessible) async {
            box.increment()
            await cacheThumbnail(ImageCacheTests.image(side: 10), for: itemId)
        }
    }

    @MainActor
    private static func controller() -> (controller: ProbeCacheController, box: CountingBox) {
        let box = CountingBox()
        return (ProbeCacheController(box: box), box)
    }

    @Test("A cached thumbnail is served from memory, and removing it removes the disk copy too")
    @MainActor
    func thumbnailMemoryAndRemoval() async {
        let (cache, _) = Self.controller()
        let id = UUID()
        defer { Task { await cache.thumbnailCacheController.removeObject(for: id) } }
        #expect(await cache.thumbnail(for: id) == nil)

        await cache.cacheThumbnail(Self.image(side: 10), for: id)
        #expect(await cache.thumbnailCacheController.hasObject(for: id))

        #expect(await cache.thumbnail(for: id) != nil)
        await cache.thumbnailCacheController.removeObject(for: id)
        #expect(await cache.thumbnail(for: id) == nil, "removing a thumbnail removes its disk copy too")
    }

    @Test("A thumbnail that is on disk but not in memory is read from disk and cached again")
    @MainActor
    func thumbnailFallsBackToDisk() async {
        let (cache, _) = Self.controller()
        let id = UUID()
        defer { Task { await cache.thumbnailCacheController.removeObject(for: id) } }
        // Written to disk only, as a previous app launch left it.
        await cache.thumbnailCacheController.saveToDisk(Self.image(side: 10), for: id)
        #expect(await !cache.thumbnailCacheController.hasObject(for: id))

        let thumbnail = await cache.thumbnail(for: id)

        #expect(thumbnail != nil)
        #expect(await cache.thumbnailCacheController.hasObject(for: id), "the disk hit fills the memory cache")
    }

    @Test("thumbnailId creates a missing thumbnail once and serves later requests from the cache")
    @MainActor
    func thumbnailIdCreatesOnce() async {
        let (cache, box) = Self.controller()
        let id = UUID()
        let item = FakeItemModel(name: "Test")
        defer { Task { await cache.thumbnailCacheController.removeObject(for: id) } }

        let first = await cache.thumbnailId(for: id, item: item)
        let second = await cache.thumbnailId(for: id, item: item)

        #expect(first == id)
        #expect(second == id)
        #expect(box.count == 1)
    }

    @Test("thumbnailId finds a thumbnail left on disk without creating it again")
    @MainActor
    func thumbnailIdUsesDisk() async {
        let (cache, box) = Self.controller()
        let id = UUID()
        defer { Task { await cache.thumbnailCacheController.removeObject(for: id) } }
        await cache.thumbnailCacheController.saveToDisk(Self.image(side: 10), for: id)

        let result = await cache.thumbnailId(for: id, item: FakeItemModel(name: "Test"))

        #expect(result == id)
        #expect(box.count == 0)
    }

    @Test("A cancelled thumbnail request creates nothing")
    @MainActor
    func cancelledThumbnailRequest() async {
        let (cache, box) = Self.controller()
        let id = UUID()
        let item = FakeItemModel(name: "Test")

        let task = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            return await cache.thumbnailId(for: id, item: item)
        }
        task.cancel()
        let result = await task.value

        #expect(result == nil)
        #expect(box.count == 0)
    }

    @Test("remove(itemId:) clears memory, the observable cache and the thumbnail's disk copy")
    @MainActor
    func removeClearsEverything() async {
        let (cache, _) = Self.controller()
        let id = UUID()
        await cache.imageCacheController.setObject(Self.image(), for: id)
        await cache.cacheThumbnail(Self.image(side: 10), for: id)
        cache.setCachedImage(Self.image(), for: id)
        cache.setCachedThumbnail(Self.image(), for: id)

        await cache.remove(itemId: id)

        #expect(await !cache.imageCacheController.hasObject(for: id))
        #expect(await cache.thumbnail(for: id) == nil)
        #expect(cache.cachedImage(for: id) == nil)
        #expect(cache.cachedThumbnail(for: id) == nil)
    }

    @Test("remove(itemId:includeImage: false) keeps the full image")
    @MainActor
    func removeKeepsTheImageOnRequest() async {
        let (cache, _) = Self.controller()
        let id = UUID()
        await cache.imageCacheController.setObject(Self.image(), for: id)
        cache.setCachedImage(Self.image(), for: id)
        await cache.cacheThumbnail(Self.image(side: 10), for: id)

        await cache.remove(itemId: id, includeImage: false)
        defer { Task { await cache.imageCacheController.removeObject(for: id) } }

        #expect(await cache.imageCacheController.hasObject(for: id))
        #expect(cache.cachedImage(for: id) != nil)
        #expect(await cache.thumbnail(for: id) == nil)
    }

    @Test("photo(for:) hands out the cached image at its pixel size, and nothing for an unknown id")
    @MainActor
    func photoIsACopy() async {
        let (cache, _) = Self.controller()
        let id = UUID()
        let original = Self.image(side: 6)
        await cache.imageCacheController.setObject(original, for: id)
        defer { Task { await cache.imageCacheController.removeObject(for: id) } }

        let copy = await cache.photo(for: id)

        #expect(copy != nil)
        #expect(copy?.size == original.size)
        #if os(macOS)
        // An `NSImage` is mutable, so the shared instance must not be handed out.
        #expect(copy !== original)
        #endif
        #expect(await cache.photo(for: UUID()) == nil)
    }

    @Test("A nil thumbnail is not cached")
    @MainActor
    func nilThumbnailIsNotCached() async {
        let (cache, _) = Self.controller()
        let id = UUID()

        await cache.cacheThumbnail(nil, for: id)

        #expect(await !cache.thumbnailCacheController.hasObject(for: id))
        #expect(await cache.thumbnailCacheController.loadFromDisk(for: id) == nil)
    }
}
#endif
