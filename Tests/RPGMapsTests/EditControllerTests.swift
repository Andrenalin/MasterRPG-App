// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import CharacterRPG
import Testing

@testable import MapRPG

struct EditControllerTests {
    @Test func addEntry() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = await root.itemController.itemDataModel.items[0]
        let item = await root.itemController.itemOrEmpty(for: itemId)
        
        let sut = root.editController
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .map))
        
        let entries = item.entries
        #expect(item.entries.count == 13)

        let modifiedMap = item.copy()
        let isHex = await sut.toggleHexMap(for: modifiedMap)
        #expect(isHex)
        #expect(sut.editEntries(for: item).count == 13)
        #expect(sut.editEntries(for: item) == entries)
        #expect(item.entries.count == 13)

        let entryId = UUID()
        let entry = MapEntryModel(id: entryId, name: "Name Eingang", content: "Was ist in 7a", coordinates: [])
        await sut.add(entry: entry, into: item.id)

        #expect(item.entries.count == 14)
        #expect(item.entries[13].id == entryId)
        #expect(item.entries[13].name == "Name Eingang")
        #expect(item.entries[13].content == "Was ist in 7a")
    }
}
#endif
