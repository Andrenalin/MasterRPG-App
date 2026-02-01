// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import CharacterRPG
import Testing

@testable import AdventureRPG

struct EditControllerTests {
    @Test func mergeEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController
        let itemId = await root.itemController.itemDataModel.items[0]

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .adventure))
        let item = await root.itemController.itemOrEmpty(for: itemId).copy()
        let originalEntries = item.entries
        
        item.entries[0].content = "New Content"
        var result = await sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)
        
        let savedItem = await root.itemController.itemOrEmpty(for: itemId)

        #expect(savedItem.entries[0].id == originalEntries[0].id)
        #expect(savedItem.entries[0].content == "New Content")
        
        let newEntry = AdventureEntryModel(id: UUID(), name: "Newbee", content: "Super")
        item.entries.append(newEntry)
        result = await sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        for (index, entry) in originalEntries.enumerated() {
            #expect(savedItem.entries[index].id == entry.id)
        }
        #expect(savedItem.entries.last?.id == newEntry.id)
        
        let middleEntry = AdventureEntryModel(id: UUID(), name: "Middle", content: "Super")
        item.entries.insert(middleEntry, at: 4)
        result = await sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        for (index, entry) in originalEntries.enumerated() {
            if index < 4 {
                #expect(savedItem.entries[index].id == entry.id)
            } else if index == 4 {
                #expect(savedItem.entries[4].id == middleEntry.id)
            } else {
                #expect(savedItem.entries[index + 1].id == entry.id)
            }
        }
    }
}
#endif
