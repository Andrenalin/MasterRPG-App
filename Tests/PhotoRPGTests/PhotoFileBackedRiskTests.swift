// @copyright André Trettin

#if canImport(Testing)
import CoreData
import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

/// CODE_AUDIT_26 §10.19: the photo file paths a bad file or a picker can reach.
@MainActor
@Suite("Photo file-backed risks", .serialized)
struct PhotoFileBackedRiskTests {
    private func makeRoot() throws -> PhotoRootModel {
        let store = try InMemoryStore(bundles: [CoreRPG.Resources.bundle, PhotoRPG.Resources.bundle])
        return PhotoRootModel.persistentTestRoot(context: store.context)
    }

    private func photoWithFile(named filename: String, in root: PhotoRootModel) -> UUID {
        let itemId = UUID()
        let fileUrl = FileUrl(
            fileId: itemId,
            url: URL.temporaryDirectory.appending(path: filename),
            location: .local,
            module: "PhotoRisk",
            relativeUrl: nil
        )
        root.itemController.replace(model: PhotoModel(id: itemId, name: "Photo", fileUrl: fileUrl), isInsert: true)
        return itemId
    }

    @Test("Extensions are compared without regard to case", arguments: [
        (name: "IMG.JPG", isNotJpeg: false),
        (name: "scan.Jpeg", isNotJpeg: false),
        (name: "shot.jpe", isNotJpeg: false),
        (name: "photo.png", isNotJpeg: true),
        (name: "map.HEIC", isNotJpeg: true)
    ])
    func jpegDetectionIgnoresCase(name: String, isNotJpeg: Bool) throws {
        let root = try makeRoot()
        let itemId = photoWithFile(named: name, in: root)

        #expect(root.editController.isNotJpegPhoto(itemId: itemId) == isNotJpeg)
    }

    @Test("An item without a file is not reported as a non-JPEG")
    func itemWithoutFileIsNotNonJpeg() throws {
        let root = try makeRoot()
        let itemId = UUID()
        root.itemController.replace(model: PhotoModel(id: itemId, name: "Empty"), isInsert: true)

        #expect(root.editController.isNotJpegPhoto(itemId: itemId) == false)
        #expect(root.editController.isNotJpegPhoto(itemId: UUID()) == false)
    }

    @Test("Data that is no image is refused and leaves the item untouched", arguments: [
        Data("definitely not an image".utf8),
        Data(),
        Data(repeating: 0xFF, count: 64)
    ])
    func nonImageDataIsRefused(data: Data) async throws {
        let root = try makeRoot()
        let itemId = photoWithFile(named: "photo.jpg", in: root)
        let before = root.itemController.itemOrEmpty(for: itemId).fileUrl

        let replaced = try await root.editController.resetPhoto(data: data, itemId: itemId, forceSave: true)

        #expect(replaced == false)
        #expect(root.itemController.itemOrEmpty(for: itemId).fileUrl == before)
    }
}
#endif
