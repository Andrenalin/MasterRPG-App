// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG
@testable import PhotoRPG

/// "Generate Map" in the game's photo list: a map from a photo that exists in game memory only.
@MainActor
@Suite("Temporary map from a photo")
struct TemporaryMapTests {
    private func photoId(in root: MapRootModel) throws -> UUID {
        let photos = root.photoRoot.itemControllable
        return try #require(photos.itemDataModel.items.first { photos.itemSync(for: $0)?.specialCategory == false })
    }

    @Test("The map is in game memory only, uses the photo and is ready to be shown")
    func createsGameOnlyMap() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        root.itemController.itemDataModel.resetGame(start: true)
        let libraryCount = root.itemController.itemDataModel.items.count

        let reference = try #require(await root.gameController.createTemporaryMap(photoId: photoId))

        #expect(reference.type == .map)
        let map = root.gameController.gameItem(for: reference.id)
        #expect(map.id == reference.id)
        #expect(map.photoId == photoId)
        #expect(map.width > 0 && map.height > 0)
        #expect(map.name == root.photoRoot.itemControllable.nameSync(itemId: photoId))
        // Not in the library: not listed, not stored, not in a saved game.
        #expect(root.itemController.itemDataModel.items.count == libraryCount)
        #expect(!root.itemController.itemDataModel.items.contains(reference.id))
        #expect(root.itemController.itemSync(for: reference.id, noGame: true) == nil)
        // The players can be served its package.
        let package = try await root.gameController.createMapGameData(for: reference.id)
        #expect(package.id == reference.id)
        #expect(package.data?.isEmpty == false)
    }

    @Test("Every call makes a new map")
    func newMapEachTime() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        root.itemController.itemDataModel.resetGame(start: true)

        let first = try #require(await root.gameController.createTemporaryMap(photoId: photoId))
        let second = try #require(await root.gameController.createTemporaryMap(photoId: photoId))

        #expect(first.id != second.id)
    }

    @Test("Ending the game removes the map")
    func gameResetRemovesMap() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        root.itemController.itemDataModel.resetGame(start: true)
        let reference = try #require(await root.gameController.createTemporaryMap(photoId: photoId))

        await root.gameController.reset()

        #expect(root.itemController.itemSync(for: reference.id) == nil)
    }

    @Test("Without a running game nothing is created")
    func noGameNoMap() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)

        let reference = await root.gameController.createTemporaryMap(photoId: photoId)

        #expect(reference == nil)
    }
}
#endif
