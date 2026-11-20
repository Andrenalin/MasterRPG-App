// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG
@testable import PhotoRPG

/// "Generate New Character" and "Generate Clone Character" in the editor's photo list.
@MainActor
@Suite("Character generated from a photo")
struct GenerateFromPhotoTests {
    private func photoId(in root: CharacterRootModel) throws -> UUID {
        let photos = root.photoRoot.itemControllable
        return try #require(photos.itemDataModel.items.first { photos.itemSync(for: $0)?.specialCategory == false })
    }

    /// A Character with entries.
    private func character(in root: CharacterRootModel) -> ValueModel? {
        let items = root.itemController
        return items.itemDataModel.items.lazy
            .compactMap { items.itemSync(for: $0, noGame: true) }
            .first { !$0.specialCategory && !$0.entries.isEmpty }
    }

    @Test("A new Character is a library item named like the photo with the photo as portrait")
    func createsCharacter() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let name = root.photoRoot.itemControllable.nameSync(itemId: photoId)
        let libraryCount = root.itemController.itemDataModel.items.count

        let characterId = try #require(await root.valueActions.quickCharacter(name, photoId))

        let character = try #require(root.itemController.itemSync(for: characterId, noGame: true))
        #expect(character.name == name)
        #expect(character.photoId == photoId)
        #expect(character.photos == [photoId])
        #expect(root.itemController.itemDataModel.items.count == libraryCount + 1)
    }

    @Test("A clone is a new Character with the entries of the original and the new photo only")
    func clonesCharacter() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let original = try #require(character(in: root))
        let originalPhotoId = original.photoId
        let originalPhotos = original.photos
        let libraryCount = root.itemController.itemDataModel.items.count

        let copyId = try #require(await root.valueActions.cloneCharacter(original.id, photoId))

        #expect(copyId != original.id)
        let copy = try #require(root.itemController.itemSync(for: copyId, noGame: true))
        #expect(copy.photoId == photoId)
        #expect(copy.photos == [photoId])
        #expect(copy.entries.count == original.entries.count)
        // The copy brings copies of the groups its entries link to, so at least one item is new.
        #expect(root.itemController.itemDataModel.items.count >= libraryCount + 1)
        #expect(root.itemController.itemDataModel.items.contains(copyId))
        // The original keeps its own portrait.
        let unchanged = try #require(root.itemController.itemSync(for: original.id, noGame: true))
        #expect(unchanged.photoId == originalPhotoId)
        #expect(unchanged.photos == originalPhotos)
    }

    @Test("Cloning a missing Character or a folder makes nothing")
    func cloneRefusesWhatIsNotACharacter() async throws {
        let root = try await MockRoot.importTestData()
        let photoId = try photoId(in: root)
        let folderId = await root.itemController.addNew(type: .folder)
        let libraryCount = root.itemController.itemDataModel.items.count

        let missing = await root.valueActions.cloneCharacter(UUID(), photoId)
        #expect(missing == nil)
        let folder = await root.valueActions.cloneCharacter(folderId, photoId)
        #expect(folder == nil)
        #expect(root.itemController.itemDataModel.items.count == libraryCount)
    }
}
#endif
