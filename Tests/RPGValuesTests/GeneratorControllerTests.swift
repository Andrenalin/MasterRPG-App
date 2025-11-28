// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

struct GeneratorControllerTests {
    let rootItemId = UUID(uuidString: "C85EF4A9-910D-4989-83C9-44ED00677751")!
    
    @Test func selectItems() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.valueGeneratorTestData, itemCounter: 21)
        let item = await root.itemController.itemOrEmpty(for: rootItemId)
        #expect(item.name == "DS Charakter Template")

        let sut = await GeneratorController(root: root, rootItemId: rootItemId, saveId: nil)

        let firstEntry = item.entries[0]
        let selection = ItemRowModel(itemId: rootItemId, entryId: firstEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection, old: false)
        await #expect(sut.selectedItems() == [selection])

        let secondEntry = item.entries[1]
        let selection2 = ItemRowModel(itemId: rootItemId, entryId: secondEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection2, old: false)
        await #expect(sut.selectedItems() == [selection, selection2])

        let thirdEntry = item.entries[2]
        let selection3 = ItemRowModel(itemId: rootItemId, entryId: thirdEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection3, old: false)
        await #expect(sut.selectedItems() == [selection, selection2, selection3])

        await sut.addSelectItem(itemModel: selection2, old: false)
        await #expect(sut.selectedItems() == [selection, selection3])

        await sut.addSelectItem(itemModel: selection2, old: false)
        await #expect(sut.selectedItems() == [selection, selection2, selection3])

        // first sub
        let firstItem = await root.itemController.itemOrEmpty(for: firstEntry.valueId!)
        let secondSubEntry = firstItem.entries[1]
        let subSelection2 = ItemRowModel(itemId: firstItem.id, entryId: secondSubEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection2, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection2, selection2, selection3])

        let firstSubEntry = firstItem.entries[0]
        let subSelection1 = ItemRowModel(itemId: firstItem.id, entryId: firstSubEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection1, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection2, selection2, selection3])

        let forthSubEntry = firstItem.entries[3]
        let subSelection4 = ItemRowModel(itemId: firstItem.id, entryId: forthSubEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection4, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection2, subSelection4, selection2, selection3])

        let thirdSubEntry = firstItem.entries[2]
        let subSelection3 = ItemRowModel(itemId: firstItem.id, entryId: thirdSubEntry.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection3, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection2, subSelection3, subSelection4, selection2, selection3])

        await sut.addSelectItem(itemModel: subSelection2, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, selection3])

        // third sub
        let thirdItem = await root.itemController.itemOrEmpty(for: thirdEntry.valueId!)
        let secondSubEntry3 = thirdItem.entries[1]
        let subSelection32 = ItemRowModel(itemId: thirdItem.id, entryId: secondSubEntry3.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection32, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, selection3, subSelection32])

        // second sub
        let secondItem = await root.itemController.itemOrEmpty(for: secondEntry.valueId!)
        let firstSubEntry2 = secondItem.entries[0]
        let subSelection21 = ItemRowModel(itemId: secondItem.id, entryId: firstSubEntry2.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection21, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, subSelection21, selection3, subSelection32])

        // back and forth
        let firstSubEntry3 = thirdItem.entries[0]
        let subSelection31 = ItemRowModel(itemId: thirdItem.id, entryId: firstSubEntry3.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection31, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, subSelection21, selection3, subSelection31, subSelection32])

        let forthSubEntry2 = secondItem.entries[3]
        let subSelection24 = ItemRowModel(itemId: secondItem.id, entryId: forthSubEntry2.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection24, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, subSelection21, subSelection24, selection3, subSelection31, subSelection32])

        let thirdSubEntry3 = thirdItem.entries[2]
        let subSelection33 = ItemRowModel(itemId: thirdItem.id, entryId: thirdSubEntry3.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection33, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, subSelection21, subSelection24, selection3, subSelection31, subSelection32, subSelection33])

        let secondSubEntry2 = secondItem.entries[1]
        let subSelection22 = ItemRowModel(itemId: secondItem.id, entryId: secondSubEntry2.id, typeId: .value)
        await sut.addSelectItem(itemModel: subSelection22, old: false)
        await #expect(sut.selectedItems() == [selection, subSelection1, subSelection3, subSelection4, selection2, subSelection21, subSelection22, subSelection24, selection3, subSelection31, subSelection32, subSelection33])
    }
    
    @Test func selectItems3Levels() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.valueGeneratorTestData, itemCounter: 21)
        let item = await root.itemController.itemOrEmpty(for: rootItemId)
        #expect(item.name == "DS Charakter Template")

        let sut = await GeneratorController(root: root, rootItemId: rootItemId, saveId: nil)

        let entry4 = item.entries[3]
        let selection4 = ItemRowModel(itemId: rootItemId, entryId: entry4.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection4, old: false)
        await #expect(sut.selectedItems() == [selection4])

        let item4 = await root.itemController.itemOrEmpty(for: entry4.valueId!)
        let entry41 = item4.entries[0]
        let selection41 = ItemRowModel(itemId: item4.id, entryId: entry41.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection41, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41])

        let item41 = await root.itemController.itemOrEmpty(for: entry41.valueId!)
        let entry411 = item41.entries[0]
        let selection411 = ItemRowModel(itemId: item41.id, entryId: entry411.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection411, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411])

        let entry5 = item.entries[4]
        let selection5 = ItemRowModel(itemId: rootItemId, entryId: entry5.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection5, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection5])
    }
    
    @Test func generateModel() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.valueGeneratorTestData, itemCounter: 21)
        let item = await root.itemController.itemOrEmpty(for: rootItemId)
        #expect(item.name == "DS Charakter Template")
        let newRowModel = await root.itemController.addNew(type: nil)
        
        let sut = await GeneratorController(root: root, rootItemId: rootItemId, saveId: newRowModel.itemId)

        let entry4 = item.entries[3]
        let selection4 = ItemRowModel(itemId: rootItemId, entryId: entry4.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection4, old: false)
        await #expect(sut.selectedItems() == [selection4])

        let item4 = await root.itemController.itemOrEmpty(for: entry4.valueId!)
        let entry41 = item4.entries[0]
        let selection41 = ItemRowModel(itemId: item4.id, entryId: entry41.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection41, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41])

        let item41 = await root.itemController.itemOrEmpty(for: entry41.valueId!)
        let entry411 = item41.entries[0]
        let selection411 = ItemRowModel(itemId: item41.id, entryId: entry411.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection411, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411])

        let link41 = await sut.genDataModel.tableValueLinks[entry411.id]?.first
        let tableGen41 = await sut.genDataModel.tableGenerators[ItemRowModel(itemId: link41!.itemId, typeId: .table)]
        let child41 = await tableGen41!.children(for: ItemRowModel(itemId: tableGen41!.replacementId, typeId: .table)).first

        try #require(child41 != nil)
        let selection411T = ItemRowModel(itemId: child41!.itemId, entryId: child41?.entryId, typeId: child41!.typeId)
        await sut.addSelectItem(itemModel: selection411T, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T])

        let entry42 = item4.entries[1]
        let selection42 = ItemRowModel(itemId: item4.id, entryId: entry42.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection42, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T, selection42])

        let item42 = await root.itemController.itemOrEmpty(for: entry42.valueId!)
        let entry421 = item42.entries[0]
        let selection421 = ItemRowModel(itemId: item42.id, entryId: entry421.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection421, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T, selection42, selection421])

        let link42 = await sut.genDataModel.tableValueLinks[entry421.id]?.first
        let tableGen42 = await sut.genDataModel.tableGenerators[ItemRowModel(itemId: link42!.itemId, typeId: .table)]
        let child42 = await tableGen42!.children(for: ItemRowModel(itemId: tableGen42!.replacementId, typeId: .table)).first

        let selection421T = ItemRowModel(itemId: child42!.itemId, entryId: child42?.entryId, typeId: child42!.typeId)
        await sut.addSelectItem(itemModel: selection421T, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T, selection42, selection421, selection421T])

        let entry43 = item4.entries[2]
        let selection43 = ItemRowModel(itemId: item4.id, entryId: entry43.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection43, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T, selection42, selection421, selection421T, selection43])

        let item43 = await root.itemController.itemOrEmpty(for: entry43.valueId!)
        let entry431 = item43.entries[0]
        let selection431 = ItemRowModel(itemId: item43.id, entryId: entry431.id, typeId: .value)
        await sut.addSelectItem(itemModel: selection431, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T, selection42, selection421, selection421T, selection43, selection431])

        let link43 = await sut.genDataModel.tableValueLinks[entry431.id]?.first
        let tableGen43 = await sut.genDataModel.tableGenerators[ItemRowModel(itemId: link43!.itemId, typeId: .table)]
        let child43 = await tableGen43!.children(for: ItemRowModel(itemId: tableGen43!.replacementId, typeId: .table)).first

        let selection431T = ItemRowModel(itemId: child43!.itemId, entryId: child43?.entryId, typeId: child43!.typeId)
        await sut.addSelectItem(itemModel: selection431T, old: false)
        await #expect(sut.selectedItems() == [selection4, selection41, selection411, selection411T, selection42, selection421, selection421T, selection43, selection431, selection431T])

        await sut.createValue(name: "Test Super Item")
        
        // check created Values
        let newItem = await root.itemController.itemOrEmpty(for: newRowModel.itemId)
        let newEntries = newItem.entries
        #expect(newEntries.count == 1)
        #expect(newEntries[0].name == "Gegenstände")

        let newItem1 = await root.itemController.itemOrEmpty(for: newEntries[0].valueId!)
        let newEntries1 = newItem1.entries
        #expect(newEntries1.count == 3)
        #expect(newEntries1[0].name == "Ausrústung")
        #expect(newEntries1[1].name == "Mag. Gegenstände")
        #expect(newEntries1[2].name == "Tränke")

        let newItem11 = await root.itemController.itemOrEmpty(for: newEntries1[0].valueId!)
        let newEntries11 = newItem11.entries
        #expect(newEntries11.count == 1)
        #expect(newEntries11[0].name.withoutLink() == "Angelhaken und Schnur")

        let newItem12 = await root.itemController.itemOrEmpty(for: newEntries1[1].valueId!)
        let newEntries12 = newItem12.entries
        #expect(newEntries12.count == 1)
        #expect(newEntries12[0].name.withoutLink() == "Aderschlitz")

        let newItem13 = await root.itemController.itemOrEmpty(for: newEntries1[2].valueId!)
        let newEntries13 = newItem13.entries
        #expect(newEntries13.count == 1)
        #expect(newEntries13[0].name.withoutLink() == "Abklingtrank")
    }
}
#endif
