// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGTables
import RPGResourcesDebug
import Testing

@testable import RPGValues

struct ItemControllerTests {
    @Test func duplicate() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.itemController
        
        await root.linkController.validateParentId()
        let originalId = await root.itemController.itemDataModel.items[0]
        #expect(originalId == UUID(uuidString: "E8AB89DA-4BB7-4C6E-BD6F-88A5AC5A8358")!)
        let beforeItemIds = await root.itemController.itemDataModel.items
        #expect(beforeItemIds.count == 15)
        let item = await root.itemController.itemOrEmpty(for: originalId)
        #expect(item.entries.count == 11)
        #expect(nil == item.parentId)
        
        for subitemId in item.entries.compactMap({ $0.valueId }) {
            let subitem = await root.itemController.itemOrEmpty(for: subitemId)
            #expect(subitem.parentId == originalId)
        }

        await sut.duplicate(model: ItemRowModel(itemId: originalId, typeId: .value))
        await #expect(root.itemController.itemDataModel.items.count == 30)

        let newItemIds = await root.itemController.itemDataModel.items.filter { !beforeItemIds.contains($0) }
        let copiedItem = await root.itemController.itemOrEmpty(for: newItemIds[0])
        #expect(copiedItem.name.hasPrefix(item.name))
        #expect(copiedItem.entries.count == 11)
        #expect(nil == copiedItem.parentId)

        for (index, entry) in copiedItem.entries.enumerated() {
            guard let valueId = entry.valueId else { continue }
            #expect(item.entries[index].valueId != valueId)
            let subCopy = await root.itemController.itemOrEmpty(for: valueId)
            let subOrig = await root.itemController.itemOrEmpty(for: item.entries[index].valueId!)
            #expect(!subCopy.isSame(subOrig))
            #expect(subCopy.parentId == copiedItem.id)
            #expect(subOrig.parentId == item.id)
        }
    }
}
#endif
