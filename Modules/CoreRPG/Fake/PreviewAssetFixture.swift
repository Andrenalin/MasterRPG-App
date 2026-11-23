// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if DEBUG
import RPGResourcesDebug
import Synchronization
#endif

/// Real media used by previews and snapshot tests.
///
/// The API is available in every build configuration so preview declarations
/// also compile in Release. The large resource framework is referenced only by
/// the Debug implementation and is therefore not linked into Release products.
public enum PreviewAssetFixture {
    public enum Photo: CaseIterable, Sendable {
        case adventure
        case paladin
        case wizard
    }

    public enum File: Sendable {
        case audio
        case pdf
        case space
    }

    @MainActor
    public static func image(_ photo: Photo) -> AKImage? {
#if DEBUG
        ResourcesDebug.cachePhotoPreviewImage(named: photo.resourceName)
#else
        nil
#endif
    }

    public static func url(_ file: File) -> URL? {
#if DEBUG
        let bundledUrl: URL? = switch file {
        case .audio:
            ResourcesDebug.audioExampleURL
        case .pdf:
            ResourcesDebug.pdfExampleURL
        case .space:
            ResourcesDebug.spaceExampleURL
        }
        return bundledUrl.map(stableUrl(for:))
#else
        nil
#endif
    }

#if DEBUG
    /// The folder the example files are copied to, the same on every machine and in every build.
    private static let stableFolder = URL(filePath: "/tmp/MasterRPGPreviewAssets", directoryHint: .isDirectory)
    private static let copyLock = Mutex(())

    /// The path of a bundled example file contains the DerivedData folder, which differs per
    /// machine, per Xcode run and per `run_snapshot_tests.sh` process. Views such as the audio and
    /// Pdf detail editors print the file path, so every snapshot containing one would only match
    /// where it was recorded. The file is therefore copied to a fixed folder and that path is
    /// handed out instead. Falls back to the bundled file when the copy is not possible (for
    /// example in a sandboxed macOS test host).
    private static func stableUrl(for bundledUrl: URL) -> URL {
        let copyUrl = stableFolder.appending(path: bundledUrl.lastPathComponent, directoryHint: .notDirectory)
        return copyLock.withLock { _ in
            let fileManager = FileManager.default
            let copyPath = copyUrl.path(percentEncoded: false)
            do {
                let bundledSize = try bundledUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let copySize = try? copyUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if copySize == nil || copySize != bundledSize {
                    try fileManager.createDirectory(at: stableFolder, withIntermediateDirectories: true)
                    if fileManager.fileExists(atPath: copyPath) {
                        try fileManager.removeItem(at: copyUrl)
                    }
                    try fileManager.copyItem(at: bundledUrl, to: copyUrl)
                }
                return copyUrl
            } catch {
                return bundledUrl
            }
        }
    }
#endif

    public static func fileUrl(
        _ file: File,
        fileId: UUID,
        module: String
    ) -> FileUrl? {
        guard let url = url(file) else { return nil }
        return FileUrl(
            fileId: fileId,
            url: url,
            location: .other,
            module: module,
            relativeUrl: nil
        )
    }

    @MainActor
    public static func photoFileUrl(
        _ photo: Photo,
        fileId: UUID,
        module: String
    ) -> FileUrl? {
        guard let data = image(photo)?.jpegData(compressionQuality: JPEGQuality.export) else {
            return nil
        }
        // A fixed, machine independent path. `FileUrl(string: "", unconvertedData:)` stores
        // `URL(filePath: "")`, which resolves to the working directory of the process, and the
        // detail editor prints that path: the simulator's data folder, with the user name and the
        // device UUID of whoever recorded the snapshot (CI rendered `Users/local/.../<its UUID>`).
        // No file extension, as before: `ConvertImageEditor` offers "Convert to JPEG" only for a
        // file that is not a JPEG yet, and the snapshots of it rely on that.
        var fileUrl = FileUrl(
            fileId: fileId,
            url: URL(filePath: "/Preview/\(module)/\(fileId.uuidString)"),
            location: .appCloud,
            module: module,
            relativeUrl: nil
        )
        fileUrl.resetData(data)
        return fileUrl
    }

    @MainActor
    static func cachePhotoViewFixture(
        _ photo: Photo
    ) -> (cacheController: any ImageCacheControllable, model: any ItemDataAccessible) {
        let model = FakeItemModel(name: photo.title)
        let cacheController = FakeImageCacheController()

        if let image = image(photo) {
            cacheController.setCachedImage(image, for: model.id)
            cacheController.setCachedThumbnail(image, for: model.id)
        }

        return (cacheController, model)
    }
}

private extension PreviewAssetFixture.Photo {
    var resourceName: String {
        switch self {
        case .adventure:
            "Adventure"
        case .paladin:
            "Paladin"
        case .wizard:
            "Zauberer"
        }
    }

    var title: String {
        switch self {
        case .adventure:
            "Adventure"
        case .paladin:
            "Paladin"
        case .wizard:
            "Wizard"
        }
    }
}
