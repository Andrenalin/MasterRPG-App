// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import CharacterRPG
import Testing

@testable import RPGMaps

struct EditControllerTests {
    @Test func scanMapEntries() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 3)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        
        let entryId = UUID()
        let entry = MapEntryModel(id: entryId, name: "Name Eingang und", content: "Was ist in 7a im Wurzelnest Ebene 1 und 11 Zugang aus Wurzelnest Ebene 2", coordinates: [])
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .map, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "Name Eingang und")
        #expect(updatedEntry.content == "Was ist in 7a im [Wurzelnest Ebene 1](RPG://MAPS/0/75E5264D-CE13-40F8-8C0B-091B0549701E) und 11 Zugang aus [Wurzelnest Ebene 2](RPG://MAPS/0/09C70ABC-93B1-4CC5-98A1-9810B018D18D)")

        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId).copy()
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

        result = await sut.scan(itemId: itemRowModel.itemId, with: [scanId!], module: .map, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]

        #expect(updatedEntry.name == "Name Eingang und")
        #expect(updatedEntry.content == "Was ist in [7a](RPG://MAPS/0/22BD78C1-CB43-480D-87F6-1ABE9BF1BA0B/12CA831D-2E09-45D0-990E-4D4B2A82D01C) im [Wurzelnest Ebene 1](RPG://MAPS/0/75E5264D-CE13-40F8-8C0B-091B0549701E) und [11 Zugang](RPG://MAPS/0/22BD78C1-CB43-480D-87F6-1ABE9BF1BA0B/271FB58D-93BB-43AE-9616-2DF646C6730B) aus [Wurzelnest Ebene 2](RPG://MAPS/0/09C70ABC-93B1-4CC5-98A1-9810B018D18D)")
    }

    @Test func addEntry() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .map))
        let entries = await sut.model.entries
        await #expect(sut.model.entries.count == 13)

        let isHex = await sut.toggleHexMap()
        #expect(isHex)
        await #expect(sut.editEntries.count == 13)
        await #expect(sut.editEntries == entries)
        await #expect(sut.model.entries.count == 130)

        let entryId = UUID()
        let entry = MapEntryModel(id: entryId, name: "Name Eingang", content: "Was ist in 7a", coordinates: [])
        await sut.add(entry: entry, into: sut.model.id)

        await #expect(sut.model.entries.count == 131)
        await #expect(sut.model.entries[13].id == entryId)
        await #expect(sut.model.entries[13].name == "Name Eingang")
        await #expect(sut.model.entries[13].content == "Was ist in 7a")
    }
}
#endif
