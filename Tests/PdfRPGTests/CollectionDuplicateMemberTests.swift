// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import PdfRPG

/// CODE_AUDIT_28 §5.2: a collection lists a member once. The second entry had the member's id
/// again, was persisted as a second row with one uuid and dropped by the next save.
@Suite(.serialized)
@MainActor
struct CollectionDuplicateMemberTests {
    @Test("Adding a member to a collection a second time keeps one entry")
    func secondAddIsRejected() async throws {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()
        let collectionId = await root.itemController.addNew(type: root.itemController.collectionCategory)
        let memberId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Shelf", itemId: collectionId)
        root.editController.reset(name: "Book", itemId: memberId)

        root.editController.addItem(itemId: memberId, parentId: collectionId)
        root.editController.addItem(itemId: memberId, parentId: collectionId)

        let collection = root.itemController.itemOrEmpty(for: collectionId)
        #expect(collection.entries.map(\.childId) == [memberId])
    }
}
#endif
