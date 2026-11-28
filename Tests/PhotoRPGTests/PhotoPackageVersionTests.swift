// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import PhotoRPG

/// CODE_AUDIT_Edit_Save §5.10: a metadata edit of a file-backed item changes the package version
/// (so a player who holds the file asks for the new package) but not the asset version (so the
/// file bytes do not travel again).
@Suite("Photo package version covers metadata")
@MainActor
struct PhotoPackageVersionTests {
    @Test("A rename changes the package version, not the asset version")
    func renameChangesPackageVersionOnly() async throws {
        let root = PhotoRootModel.testRoot()
        let photo = PhotoModel(id: UUID(), name: "Castle", description: "Gate")
        root.itemController.replace(model: photo, isInsert: true)
        let before = await root.gameControllable.share(id: photo.id)

        root.editController.reset(name: "Ruined Castle", itemId: photo.id, forceSave: false)
        let after = await root.gameControllable.share(id: photo.id)

        #expect(before.version != after.version, "a player holding the old name kept it")
        #expect(before.effectiveAssetVersion == after.effectiveAssetVersion, "the file would be sent again")
        #expect(after.effectiveAssetVersion == root.itemController.itemSync(for: photo.id)?.version)
    }

    @Test("A player's copy with the old metadata is not current")
    func hasItemComparesThePackageVersion() async throws {
        let root = PhotoRootModel.testRoot()
        let photo = PhotoModel(id: UUID(), name: "Castle", description: "Gate", degrees: 0)
        root.itemController.replace(model: photo, isInsert: true)
        let old = await root.gameControllable.share(id: photo.id)

        root.editController.reset(description: "Broken gate", itemId: photo.id, forceSave: false)
        let new = await root.gameControllable.share(id: photo.id)

        #expect(await root.gameControllable.hasItem(id: photo.id, version: new.version))
        #expect(await !root.gameControllable.hasItem(id: photo.id, version: old.version))
    }

    @Test("Tags are not part of the package version")
    func tagsLeaveThePackageVersion() async throws {
        let root = PhotoRootModel.testRoot()
        let photo = PhotoModel(id: UUID(), name: "Castle")
        root.itemController.replace(model: photo, isInsert: true)
        let before = await root.gameControllable.share(id: photo.id)

        root.editController.reset(tags: ["ruin"], itemId: photo.id, forceSave: false)

        #expect(await root.gameControllable.share(id: photo.id).version == before.version)
    }
}
#endif
