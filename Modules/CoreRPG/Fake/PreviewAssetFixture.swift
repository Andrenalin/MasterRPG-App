// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if DEBUG
import RPGResourcesDebug
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
        switch file {
        case .audio:
            ResourcesDebug.audioExampleURL
        case .pdf:
            ResourcesDebug.pdfExampleURL
        case .space:
            ResourcesDebug.spaceExampleURL
        }
#else
        nil
#endif
    }

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
        return FileUrl(
            string: "",
            fileId: fileId,
            module: module,
            unconvertedData: data
        )
    }

    @MainActor
    static func cachePhotoViewFixture(
        _ photo: Photo
    ) -> (cacheController: any ImageCacheControllable, model: any ItemDataAccessable) {
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
