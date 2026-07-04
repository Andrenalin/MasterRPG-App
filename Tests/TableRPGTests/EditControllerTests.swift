// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct EditControllerTests {
    @Test @MainActor func mergeEntries() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = root.itemController.itemDataModel.items[0]
        let sut = root.editController

        sut.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .table))
        let item = root.itemController.itemOrEmpty(for: itemId).copy()
        let originalEntries = item.entries

        item.entries[0].content = "New Content"
        var result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        let savedItem = root.itemController.itemOrEmpty(for: itemId)
        #expect(savedItem.entries[0].id == originalEntries[0].id)
        #expect(savedItem.entries[0].content == "New Content")

        let newEntry = TableEntryModel(id: UUID(), name: "Newbee", content: "Super", displayState: 1, diceResult: "Perfect")
        item.entries.append(newEntry)
        result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        originalEntries.enumerated().forEach { index, entry in
            #expect(savedItem.entries[index].id == entry.id)
        }
        #expect(savedItem.entries.last?.id == newEntry.id)

        let middleEntry = TableEntryModel(id: UUID(), name: "Middle", content: "Super", displayState: 1, diceResult: "Perfect")
        item.entries.insert(middleEntry, at: 4)
        result = sut.merge(itemId: itemId, entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        originalEntries.enumerated().forEach { index, entry in
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
