// @copyright André Trettin

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What identifies a cutout: the photo, the file behind it and the generator revision. A photo
/// whose file changed (new `fileId` or `contentHash`) gets a new cutout.
struct PinCutoutKey: Hashable, Sendable {
    let photoId: UUID
    let fileId: UUID?
    let contentHash: String?
    let revision: Int

    init(photoId: UUID, fileId: UUID?, contentHash: String?, revision: Int = PinCutoutPolicy.revision) {
        self.photoId = photoId
        self.fileId = fileId
        self.contentHash = contentHash
        self.revision = revision
    }

    var fileName: String {
        let file = fileId?.uuidString ?? "nofile"
        let hash = contentHash.map { String($0.prefix(16)) } ?? "nohash"
        return "\(photoId.uuidString)-\(file)-\(hash)-r\(revision).png"
    }
}

/// Memory and disk cache of the pin cutouts. Concurrent requests for the same key (several pins
/// of one monster) share one analysis. A photo without a usable subject is remembered for the
/// session only, so a changed generator revision or a re-imported file is tried again.
actor PinCutoutCache {
    static let shared = PinCutoutCache()

    private final class Box: @unchecked Sendable {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    private let memory: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 64
        return cache
    }()
    private var inFlight: [PinCutoutKey: Task<CGImage?, Never>] = [:]

    /// - Parameter source: decodes the photo downsampled to `PinCutoutPolicy.sourceMaxPixelSize`;
    ///   only called when neither cache has the key.
    func cutout(for key: PinCutoutKey, source: @escaping @Sendable () async -> CGImage?) async -> CGImage? {
        if let box = memory.object(forKey: key.fileName as NSString) { return box.image }
        if let running = inFlight[key] { return await running.value }
        let task = Task<CGImage?, Never> {
            if let stored = await Self.loadFromDisk(fileName: key.fileName) { return stored }
            guard let photo = await source() else { return nil }
            let generated = await PinCutoutGenerator.cutout(from: photo)
            if let generated { await Self.saveToDisk(generated, fileName: key.fileName) }
            return generated
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        memory.setObject(Box(result), forKey: key.fileName as NSString)
        return result
    }

    // MARK: - Disk

    private static var directory: URL {
        URL.cachesDirectory.appending(path: "PinCutouts", directoryHint: .isDirectory)
    }

    @concurrent
    private static func loadFromDisk(fileName: String) async -> CGImage? {
        let url = directory.appending(path: fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    @concurrent
    private static func saveToDisk(_ image: CGImage, fileName: String) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
