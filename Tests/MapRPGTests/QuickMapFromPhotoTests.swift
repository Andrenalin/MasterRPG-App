// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG
@testable import PhotoRPG

/// "Generate Map" in the editor's photo list: a saved library map with the photo as background.
@MainActor
@Suite("Saved map from a photo")
struct QuickMapFromPhotoTests {
    private func photoId(in root: MapRootModel) throws -> UUID {
        let photos = root.photoRoot.itemControllable
        return try #require(photos.itemDataModel.items.first { photos.itemSync(for: $0)?.specialCategory == false })
    }

    @Test("The map is a library item named like the photo and uses it as background")
    func createsLibraryMap() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let name = root.photoRoot.itemControllable.nameSync(itemId: photoId)
        let libraryCount = root.itemController.itemDataModel.items.count

        let mapId = try #require(await root.mapActions.quickMap(name, photoId))

        let map = try #require(root.itemController.itemSync(for: mapId, noGame: true))
        #expect(map.name == name)
        #expect(map.photoId == photoId)
        #expect(map.width > 0 && map.height > 0)
        #expect(root.itemController.itemDataModel.items.contains(mapId))
        #expect(root.itemController.itemDataModel.items.count == libraryCount + 1)
    }

    @Test("Generating again from the same photo reuses the map")
    func reusesMap() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let name = root.photoRoot.itemControllable.nameSync(itemId: photoId)

        let first = try #require(await root.mapActions.quickMap(name, photoId))
        let second = try #require(await root.mapActions.quickMap(name, photoId))

        #expect(first == second)
    }
}
#endif
