// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import RPGDie
import Foundation
import AudioRPG
import RPGMaps
import RPGPdfs
import PhotoRPG
import RPGResourcesDebug
import RPGTables
import RPGValues
import Testing

@testable import RPGAdventures

struct EditControllerTests {
    @Test func scanMapEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        
        let entryId = UUID()
        let entry = AdventureEntryModel(id: entryId, name: "Name Eingang und", content: "Bei der Untersuchung des Wurzelnestes findet ihr die Verbotene Türe und die 1. Kinder der Ratten erden in der Einleitung erwähnt")
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .adventure, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "Name Eingang und")
        #expect(updatedEntry.content == "Bei der [Untersuchung des Wurzelnestes](RPG://ADVENTURES/0/3DCA977D-00C2-4556-97D2-BFF83A05120E) findet ihr die Verbotene Türe und die [1. Kinder der Ratten](RPG://ADVENTURES/0/EC2C95BE-70CD-436F-B8F7-B4F962A70362) erden in der Einleitung erwähnt")

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
        
        result = await sut.scan(itemId: itemRowModel.itemId, with: [scanId!], module: .adventure, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]

        #expect(updatedEntry.name == "Name Eingang und")
        #expect(updatedEntry.content == "Bei der [Untersuchung des Wurzelnestes](RPG://ADVENTURES/0/3DCA977D-00C2-4556-97D2-BFF83A05120E) findet ihr [Die Verbotene Türe](RPG://ADVENTURES/0/D70F4601-8C80-4BE1-B412-AABA07B2566E/42561C14-8A26-4515-876B-E297262DA9BE) und die [1. Kinder der Ratten](RPG://ADVENTURES/0/EC2C95BE-70CD-436F-B8F7-B4F962A70362) erden in der [Einleitung](RPG://ADVENTURES/0/D70F4601-8C80-4BE1-B412-AABA07B2566E/EAC70DF9-BC6B-4354-905A-6DE9E342C01B) erwähnt")
    }
    
    @Test func mergeEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .adventure))
        let item = await sut.model.copy()
        let originalEntries = item.entries
        
        item.entries[0].content = "New Content"
        var result = await sut.merge(entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        await #expect(sut.model.entries[0].id == originalEntries[0].id)
        await #expect(sut.model.entries[0].content == "New Content")
        
        let newEntry = AdventureEntryModel(id: UUID(), name: "Newbee", content: "Super")
        item.entries.append(newEntry)
        result = await sut.merge(entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        for (index, entry) in originalEntries.enumerated() {
            await #expect(sut.model.entries[index].id == entry.id)
        }
        await #expect(sut.model.entries.last?.id == newEntry.id)
        
        let middleEntry = AdventureEntryModel(id: UUID(), name: "Middle", content: "Super")
        item.entries.insert(middleEntry, at: 4)
        result = await sut.merge(entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        for (index, entry) in originalEntries.enumerated() {
            if index < 4 {
                await #expect(sut.model.entries[index].id == entry.id)
            } else if index == 4 {
                await #expect(sut.model.entries[4].id == middleEntry.id)
            } else {
                await #expect(sut.model.entries[index + 1].id == entry.id)
            }
        }
    }

    @Test func validateEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .adventure))
        let model = await sut.model

        let entries = model.entries
        #expect(entries.count == 4)

        await sut.validateEntries()
        #expect(model.entries.count == 4)
        #expect(model.entries == entries)

        let brokenEntries = entries.flatMap { [$0, $0] }
        model.entries = brokenEntries
        #expect(model.entries.count == 8)

        await sut.validateEntries()
        #expect(model.entries.count == 4)
        #expect(model.entries == entries)

        await sut.validateEntries()
        #expect(model.entries.count == 4)
        #expect(model.entries == entries)
    }
}
#endif
