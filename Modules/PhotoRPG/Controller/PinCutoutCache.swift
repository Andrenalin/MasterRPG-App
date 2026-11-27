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

    /// Checked: `CGImage` is `Sendable` on every SDK. See CODE_AUDIT_29 §3.9.
    private final class Box: Sendable {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }

    private let memory: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 64
        return cache
    }()
    private var inFlight: [PinCutoutKey: Task<Outcome, Never>] = [:]
    private var hasPruned = false

    /// What one request found. Only `.cutout` and `.noSubject` are remembered: a photo that could
    /// not be read yet (not downloaded) is tried again on the next request instead of showing no
    /// cutout until relaunch. See CODE_AUDIT_29 §7.7.
    private enum Outcome: Sendable {
        case cutout(CGImage)
        case noSubject
        case sourceUnavailable

        var image: CGImage? {
            if case .cutout(let image) = self { return image }
            return nil
        }
    }

    /// - Parameter source: decodes the photo downsampled to `PinCutoutPolicy.sourceMaxPixelSize`;
    ///   only called when neither cache has the key.
    func cutout(for key: PinCutoutKey, source: @escaping @Sendable () async -> CGImage?) async -> CGImage? {
        pruneOnce()
        if let box = memory.object(forKey: key.fileName as NSString) { return box.image }
        if let running = inFlight[key] { return await running.value.image }
        let task = Task<Outcome, Never> {
            if let stored = await Self.loadFromDisk(fileName: key.fileName) { return .cutout(stored) }
            guard let photo = await source() else { return .sourceUnavailable }
            guard let generated = await PinCutoutGenerator.cutout(from: photo) else { return .noSubject }
            await Self.saveToDisk(generated, fileName: key.fileName, replacingOthersOf: key.photoId)
            return .cutout(generated)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        switch result {
        case .cutout(let image): memory.setObject(Box(image), forKey: key.fileName as NSString)
        case .noSubject: memory.setObject(Box(nil), forKey: key.fileName as NSString)
        case .sourceUnavailable: break
        }
        return result.image
    }

    /// Once per launch: removes the cutouts of older generator revisions, which no key can name
    /// any more. See CODE_AUDIT_29 §7.7.
    private func pruneOnce() {
        guard !hasPruned else { return }
        hasPruned = true
        let suffix = "-r\(PinCutoutPolicy.revision).png"
        Task.detached(priority: .utility) {
            Self.removeFiles { !$0.hasSuffix(suffix) }
        }
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

    /// Also removes the photo's cutouts of a file it no longer has.
    @concurrent
    private static func saveToDisk(_ image: CGImage, fileName: String, replacingOthersOf photoId: UUID) async {
        removeFiles { $0.hasPrefix(photoId.uuidString) && $0 != fileName }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func removeFiles(where shouldRemove: (String) -> Bool) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return }
        for name in names where shouldRemove(name) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
