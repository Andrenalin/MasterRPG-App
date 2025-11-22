// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import DiceRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import RPGTables

struct EditControllerTests {
    @Test func scanDice() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 53)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)

        let entryId = UUID()
        let entry = TableEntryModel(id: entryId, name: "4W20, Adalbert Unheil, D20, 3W20xAxt, Fegel, 5d20, Armbruste", content: "4W20, Adalbert d20 Unheil, D20, 4W20xAxt, Fegel, 4d20, d20Armbruste")
        await sut.add(entry: entry, into: itemRowModel.itemId)

        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: true, words: false)
        try #require(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "4W20, Adalbert Unheil, D20, 3W20xAxt, Fegel, 5d20, Armbruste")
        #expect(updatedEntry.content == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A)xAxt, Fegel, 4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E)Armbruste")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: true, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "4W20, Adalbert Unheil, D20, 3W20xAxt, Fegel, 5d20, Armbruste")
        #expect(updatedEntry.content == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), 4W20xAxt, Fegel, 4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), d20Armbruste")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: false, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "4W20, Adalbert Unheil, D20, 3W20xAxt, Fegel, 5d20, Armbruste")
        #expect(updatedEntry.content == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert d20 Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), 4W20xAxt, Fegel, 4d20, d20Armbruste")
    }

    @Test func scanTable() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 53)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)

        let entryId = UUID()
        let entry = TableEntryModel(id: entryId, name: "Waffen , magische gegenstände, Mega Magische und Gegenstände Beutetabelle T", content: "BeuteWaffen , nichtMagische GegenständeAlles, 5xBeutetabelle T, Beutetabelle A")
        await sut.add(entry: entry, into: itemRowModel.itemId)

        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: true, words: false)
        try #require(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "Waffen , magische gegenstände, Mega Magische und Gegenstände Beutetabelle T")
        #expect(updatedEntry.content == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D)")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: true, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "Waffen , magische gegenstände, Mega Magische und Gegenstände Beutetabelle T")
        #expect(updatedEntry.content == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , nichtMagische GegenständeAlles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), Beutetabelle A")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: false, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "Waffen , magische gegenstände, Mega Magische und Gegenstände Beutetabelle T")
        #expect(updatedEntry.content == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D)")
    }

    @Test func scanTableEntries() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 53)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)

        let entryId = UUID()
        let entry = TableEntryModel(id: entryId, name: "Will not be scanned", content: "BeuteWaffenIn Deckung Axt, nichtMagische GegenständeAlles, 5xBeutetabelle T, Blutige Heilung Beutetabelle A")
        await sut.add(entry: entry, into: itemRowModel.itemId)

        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: true, words: false)
        try #require(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "Will not be scanned")
        #expect(updatedEntry.content == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07)In Deckung Axt, nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), Blutige Heilung [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D)")

        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId).copy()
        item.entries = [updatedEntry]
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)

        var scanTableId: UUID? = nil
        for itemId in await root.itemController.itemDataModel.items {
            if await root.itemController.itemOrEmpty(for: itemId).name == "Talente" {
                scanTableId = itemId
                break
            }
        }
        #expect(scanTableId != nil)

        result = await sut.scan(itemId: itemRowModel.itemId, with: [scanTableId!], module: .table, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]

        #expect(updatedEntry.name == "Will not be scanned")
        #expect(updatedEntry.content == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07)[In Deckung](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F/15AC804A-F08F-4968-AE21-FA29DDD1FAFA) Axt, nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), [Blutige Heilung](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F/87051521-5C20-4AD1-90AA-8948D37528CE) [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D)")
    }

    @Test func scanTableEntriesWithLinks() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 53)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)

        let entryId = UUID()
        let entry = TableEntryModel(id: entryId, name: "Nothing", content: "Wir [Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) haben es")
        await sut.add(entry: entry, into: itemRowModel.itemId)

        var scanTableId: UUID? = nil
        for itemId in await root.itemController.itemDataModel.items {
            if await root.itemController.itemOrEmpty(for: itemId).name == "Beutetabelle A" {
                scanTableId = itemId
                break
            }
        }
        #expect(scanTableId != nil)

        let result = await sut.scan(itemId: itemRowModel.itemId, with: [scanTableId!], module: .table, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        let updatedEntry = result[0]

        #expect(updatedEntry.content == "Wir [Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) haben es")
    }

    @Test @MainActor func mergeEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController(type: .main)

        sut.setCurrentItem(to: ItemRowTreeModel(itemId: root.itemController.itemDataModel.items[0], typeId: .table))
        let item = sut.model.copy()
        let originalEntries = item.entries

        item.entries[0].content = "New Content"
        var result = await sut.merge(entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        #expect(sut.model.entries[0].id == originalEntries[0].id)
        #expect(sut.model.entries[0].content == "New Content")

        let newEntry = TableEntryModel(id: UUID(), name: "Newbee", content: "Super", displayState: 1, diceResult: "Perfect")
        item.entries.append(newEntry)
        result = await sut.merge(entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        originalEntries.enumerated().forEach { index, entry in
            #expect(sut.model.entries[index].id == entry.id)
        }
        #expect(sut.model.entries.last?.id == newEntry.id)

        let middleEntry = TableEntryModel(id: UUID(), name: "Middle", content: "Super", displayState: 1, diceResult: "Perfect")
        item.entries.insert(middleEntry, at: 4)
        result = await sut.merge(entries: item.entries, recoverEntries: nil)
        #expect(result.isEmpty)

        originalEntries.enumerated().forEach { index, entry in
            if index < 4 {
                #expect(sut.model.entries[index].id == entry.id)
            } else if index == 4 {
                #expect(sut.model.entries[4].id == middleEntry.id)
            } else {
                #expect(sut.model.entries[index + 1].id == entry.id)
            }
        }
    }
}
#endif
