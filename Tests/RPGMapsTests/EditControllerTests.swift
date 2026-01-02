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
    @Test func scanMapEntries() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 3)
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        
        let entryId = UUID()
        let entry = MapEntryModel(id: entryId, name: "Name Eingang und", content: "Was ist in 7a im Wurzelnest Ebene 1 und 11 Zugang aus Wurzelnest Ebene 2", coordinates: [])
        await sut.add(entry: entry, into: itemId)
        
        var result = await sut.scan(itemId: itemId, with: nil, module: .map, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "Name Eingang und")
        #expect(updatedEntry.content == "Was ist in 7a im [Wurzelnest Ebene 1](RPG://MAPS/0/75E5264D-CE13-40F8-8C0B-091B0549701E) und 11 Zugang aus [Wurzelnest Ebene 2](RPG://MAPS/0/09C70ABC-93B1-4CC5-98A1-9810B018D18D)")

        let item = await root.itemController.itemOrEmpty(for: itemId).copy()
        item.entries = [updatedEntry]
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)

        var scanId: UUID? = nil
        for itemId in await root.itemController.itemDataModel.items {
            if await root.itemController.itemOrEmpty(for: itemId).name == "Das Geheimnis des Knochenbaus" {
                scanId = itemId
                break
            }
        }
        try #require(nil != scanId)

        result = await sut.scan(itemId: itemId, with: [scanId!], module: .map, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]

        #expect(updatedEntry.name == "Name Eingang und")
        #expect(updatedEntry.content == "Was ist in [7a](RPG://MAPS/0/22BD78C1-CB43-480D-87F6-1ABE9BF1BA0B/12CA831D-2E09-45D0-990E-4D4B2A82D01C) im [Wurzelnest Ebene 1](RPG://MAPS/0/75E5264D-CE13-40F8-8C0B-091B0549701E) und [11 Zugang](RPG://MAPS/0/22BD78C1-CB43-480D-87F6-1ABE9BF1BA0B/271FB58D-93BB-43AE-9616-2DF646C6730B) aus [Wurzelnest Ebene 2](RPG://MAPS/0/09C70ABC-93B1-4CC5-98A1-9810B018D18D)")
    }

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
        #expect(item.entries.count == 130)

        let entryId = UUID()
        let entry = MapEntryModel(id: entryId, name: "Name Eingang", content: "Was ist in 7a", coordinates: [])
        await sut.add(entry: entry, into: item.id)

        #expect(item.entries.count == 131)
        #expect(item.entries[13].id == entryId)
        #expect(item.entries[13].name == "Name Eingang")
        #expect(item.entries[13].content == "Was ist in 7a")
    }
}
#endif
