// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import PhotoRPG
@testable import MapRPG
@testable import TableRPG
@testable import CharacterRPG

@MainActor
struct LinkControllerTests {
    @Test func validateLinksWithLinkReplace() async throws {
        let root = try await MockRoot.importTestData()

        let sut = root.linkController

        let photoId = UUID()
        let photo = PhotoModel(id: photoId, name: "Photo", description: "Some Text", tags: ["Some"], category: .adventure)
        root.photoRoot.editController.save(updated: photo, message: "Test")
        
        let tableEntryId = UUID()
        let tableEntry = TableEntryModel(id: tableEntryId, name: "Table", content: "Some Text")
        let tableId = UUID()
        let table = TableModel(id: tableId, name: "Table", description: "Some Text", tags: ["Some"], category: .rules, entries: [tableEntry])
        root.tableRoot.editController.save(updated: table, message: "Test")
        
        let valueEntryId = UUID()
        let valueEntry = ValueEntryModel(id: valueEntryId, name: "Value", type: .text, value: "Some Text")
        let valueId = UUID()
        let value = ValueModel(id: valueId, name: "Value", description: "Some Text", tags: ["Some"], category: .rules, entries: [valueEntry])
        root.characterRoot.editController.save(updated: value, message: "Test")
        
        var content = "Link to Photo "
        content = root.photoRoot.linkControllable.generateLinks(itemId: photoId, entryId: nil, into: content)
        let entry1 = AdventureEntryModel(id: UUID(), name: "Hello", content: content)
        
        content = root.tableRoot.linkControllable.generateLinks(itemId: tableId, entryId: tableEntryId, into: content)
        let entry2 = AdventureEntryModel(id: UUID(), name: "Hello 2", content: content)

        content = root.characterRoot.linkControllable.generateLinks(itemId: valueId, entryId: valueEntryId, into: content)
        let entry3 = AdventureEntryModel(id: UUID(), name: "Hello 3", content: content)
        
        let itemId = UUID()
        let item = AdventureModel(id: itemId, name: "Name", description: "Some Text", tags: ["Some"], category: .scenario, photoId: photoId, entries: [entry1, entry2, entry3])
        root.editController.save(updated: item, message: "Test")
        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id] == entry2)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id] == entry3)
        
        await sut.validateLinks(reportModel: ValidateRepairModel())
        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id] == entry2)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id] == entry3)

        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: photoId, typeId: .photo)).count == 4)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, typeId: .table)).count == 2)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, entryId: tableEntryId, typeId: .table)).count == 2)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, typeId: .value)).count == 1)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, entryId: valueEntryId, typeId: .value)).count == 1)

        await root.characterRoot.itemController.delete(itemId: valueId)

        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, typeId: .value)).count == 1)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, entryId: valueEntryId, typeId: .value)).count == 1)

        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id] == entry2)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id] == entry3)

        root.tableRoot.editController.setCurrentItem(to: ItemRowTreeModel(itemId: tableId, typeId: .table))
        root.tableRoot.editController.remove(itemId: tableId, entryId: tableEntryId)
        
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, typeId: .table)).count == 2)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, entryId: tableEntryId, typeId: .table)).count == 2)

        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
//        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id].content == "\(entry1.content)Table")
//        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id].content == "\(entry1.content)TableValue")
    }
}
