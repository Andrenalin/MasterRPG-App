// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

//struct EditControllerTests {
//    @Test func createGroup() async throws {
//        let root = try await MockRoot.importTestData()
//        let sut = await root.editController
//        
//        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
//        #expect(item.entries.count == 11)
//        let entry = item.entries[0]
//        #expect(entry.id == UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
//        #expect(entry.name == "Group")
//
//        // no change because editController is not set to this item
//        await sut.createGroup(itemId: item.id, entryIds: [entry.id])
//        #expect(entry.id == UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
//
//        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .value))
//        await sut.createGroup(itemId: item.id, entryIds: [entry.id])
//        
//        let groupEntry = item.entries[0]
//        #expect(groupEntry.id != UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
//        #expect(groupEntry.name == "Group")
//        #expect(groupEntry.valueId != nil)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry.valueId!).entries.count == 1)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry.valueId!).parentId == item.id)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry.valueId!).entries[0].id == entry.id)
//        #expect(item.entries.count == 11)
//
//        let entry2 = item.entries[1]
//        let entry3 = item.entries[2]
//        #expect(entry2.id == UUID(uuidString: "233BFCF5-4906-490B-A935-1952CBC8A581")!)
//        #expect(entry.name == "Group")
//        #expect(entry3.id == UUID(uuidString: "D853CABE-7EC8-4755-B717-9C952CCC8C2B")!)
//        #expect(entry.name == "Group")
//
//        await sut.createGroup(itemId: item.id, entryIds: [entry2.id, entry3.id])
//        let groupEntry2 = item.entries[1]
//        #expect(groupEntry2.id != UUID(uuidString: "233BFCF5-4906-490B-A935-1952CBC8A581")!)
//        #expect(groupEntry2.id != UUID(uuidString: "D853CABE-7EC8-4755-B717-9C952CCC8C2B")!)
//        #expect(groupEntry2.name == "Group")
//        #expect(groupEntry2.valueId != nil)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).parentId == item.id)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).entries.count == 2)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).entries[0].id == entry2.id)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).entries[1].id == entry3.id)
//        #expect(item.entries.count == 10)
//
//        let entry4 = item.entries[9]
//        let entry5 = item.entries[8]
//        let entry6 = item.entries[7]
//        #expect(entry4.id == UUID(uuidString: "304B6C77-CDCB-4000-A0D1-6C8A84070710")!)
//        #expect(entry.name == "Group")
//        #expect(entry5.id == UUID(uuidString: "479CBBB0-8BAC-4858-BA69-B917A168CE25")!)
//        #expect(entry.name == "Group")
//        #expect(entry6.id == UUID(uuidString: "5E28C6AD-BCEB-4EA8-84EE-C78C7FFE4013")!)
//        #expect(entry.name == "Group")
//
//        await sut.createGroup(itemId: item.id, entryIds: [entry4.id, entry5.id, entry6.id])
//        let groupEntry3 = item.entries[7]
//        #expect(groupEntry3.id != UUID(uuidString: "304B6C77-CDCB-4000-A0D1-6C8A84070710")!)
//        #expect(groupEntry3.name == "Group")
//        #expect(groupEntry3.valueId != nil)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).parentId == item.id)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries.count == 3)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries[0].id == entry6.id)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries[1].id == entry5.id)
//        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries[2].id == entry4.id)
//        #expect(item.entries.count == 8)
//    }
//    
//    @Test func ungroup() async throws {
//        let root = try await MockRoot.importTestData()
//        let sut = await root.editController
//
//        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
//        #expect(item.entries.count == 11)
//        let entry = item.entries[0]
//        #expect(entry.id == UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
//        #expect(entry.name == "Group")
//        #expect(entry.valueId != nil)
//        let groupValue = await root.itemController.itemOrEmpty(for: entry.valueId.unsafelyUnwrapped)
//        //#expect(groupValue.parentId, item.id) // should be not nil but test data not repaired.
//        #expect(groupValue.entries.count == 7)
//
//        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .value))
//        await sut.ungroup(from: item.id, entryIds: [entry.id])
//        await #expect(root.itemController.itemDataModel.items.count == 14)
//        await #expect(!root.itemController.itemDataModel.items.contains(groupValue.id))
//        #expect(item.entries.count == 17)
//        groupValue.entries.enumerated().forEach {
//            #expect($0.element == item.entries[$0.offset])
//        }
//    }
//    
//    @Test func scanDice() async throws {
//        // Rest of the test remains unchanged
//    }
//
//}
#endif
