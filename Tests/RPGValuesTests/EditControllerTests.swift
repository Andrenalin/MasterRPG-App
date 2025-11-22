// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGTables
import RPGResourcesDebug
import Testing

@testable import RPGValues

struct EditControllerTests {
    @Test func createGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)
        
        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        #expect(item.entries.count == 11)
        let entry = item.entries[0]
        #expect(entry.id == UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
        #expect(entry.name == "Group")

        // no change because editController is not set to this item
        await sut.createGroup(from: [entry.id])
        #expect(entry.id == UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .value))
        await sut.createGroup(from: [entry.id])
        
        let groupEntry = item.entries[0]
        #expect(groupEntry.id != UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
        #expect(groupEntry.name == "Group")
        #expect(groupEntry.valueId != nil)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry.valueId!).entries.count == 1)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry.valueId!).parentId == item.id)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry.valueId!).entries[0].id == entry.id)
        #expect(item.entries.count == 11)

        let entry2 = item.entries[1]
        let entry3 = item.entries[2]
        #expect(entry2.id == UUID(uuidString: "233BFCF5-4906-490B-A935-1952CBC8A581")!)
        #expect(entry.name == "Group")
        #expect(entry3.id == UUID(uuidString: "D853CABE-7EC8-4755-B717-9C952CCC8C2B")!)
        #expect(entry.name == "Group")

        await sut.createGroup(from: [entry2.id, entry3.id])
        let groupEntry2 = item.entries[1]
        #expect(groupEntry2.id != UUID(uuidString: "233BFCF5-4906-490B-A935-1952CBC8A581")!)
        #expect(groupEntry2.id != UUID(uuidString: "D853CABE-7EC8-4755-B717-9C952CCC8C2B")!)
        #expect(groupEntry2.name == "Group")
        #expect(groupEntry2.valueId != nil)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).parentId == item.id)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).entries.count == 2)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).entries[0].id == entry2.id)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry2.valueId!).entries[1].id == entry3.id)
        #expect(item.entries.count == 10)

        let entry4 = item.entries[9]
        let entry5 = item.entries[8]
        let entry6 = item.entries[7]
        #expect(entry4.id == UUID(uuidString: "304B6C77-CDCB-4000-A0D1-6C8A84070710")!)
        #expect(entry.name == "Group")
        #expect(entry5.id == UUID(uuidString: "479CBBB0-8BAC-4858-BA69-B917A168CE25")!)
        #expect(entry.name == "Group")
        #expect(entry6.id == UUID(uuidString: "5E28C6AD-BCEB-4EA8-84EE-C78C7FFE4013")!)
        #expect(entry.name == "Group")

        await sut.createGroup(from: [entry4.id, entry5.id, entry6.id])
        let groupEntry3 = item.entries[7]
        #expect(groupEntry3.id != UUID(uuidString: "304B6C77-CDCB-4000-A0D1-6C8A84070710")!)
        #expect(groupEntry3.name == "Group")
        #expect(groupEntry3.valueId != nil)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).parentId == item.id)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries.count == 3)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries[0].id == entry6.id)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries[1].id == entry5.id)
        await #expect(root.itemController.itemOrEmpty(for: groupEntry3.valueId!).entries[2].id == entry4.id)
        #expect(item.entries.count == 8)
    }
    
    @Test func ungroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.editController(type: .main)

        let item = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        #expect(item.entries.count == 11)
        let entry = item.entries[0]
        #expect(entry.id == UUID(uuidString: "31C20CE9-810A-4009-89AF-E1A73E45B835")!)
        #expect(entry.name == "Group")
        #expect(entry.valueId != nil)
        let groupValue = await root.itemController.itemOrEmpty(for: entry.valueId.unsafelyUnwrapped)
        //#expect(groupValue.parentId, item.id) // should be not nil but test data not repaired.
        #expect(groupValue.entries.count == 7)

        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .value))
        await sut.ungroup(from: [entry.id])
        await #expect(root.itemController.itemDataModel.items.count == 14)
        await #expect(!root.itemController.itemDataModel.items.contains(groupValue.id))
        #expect(item.entries.count == 17)
        groupValue.entries.enumerated().forEach {
            #expect($0.element == item.entries[$0.offset])
        }
    }
    
    @Test func scanDice() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 13)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        
        let entryId = UUID()
        let entry = ValueEntryModel(id: entryId, name: "4W20, Adalbert Unheil, D20, 3W20xAxt, Fegel, 5d20, Armbruste", type: .text, value: "4W20, Adalbert d20 Unheil, D20, 4W20xAxt, Fegel, 4d20, d20Armbruste")
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [3d20](RPG://DICE/0/AB7BA69C-E8BA-47F6-B183-013EA45834E0)xAxt, Fegel, 5[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), Armbruste")
        #expect(updatedEntry.value == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A)xAxt, Fegel, 4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E)Armbruste")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: true, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), 3W20xAxt, Fegel, 5[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), Armbruste")
        #expect(updatedEntry.value == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), 4W20xAxt, Fegel, 4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), d20Armbruste")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: false, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), 3W20xAxt, Fegel, 5d20, Armbruste")
        #expect(updatedEntry.value == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert d20 Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), 4W20xAxt, Fegel, 4d20, d20Armbruste")
    }
    
    @Test func scanTable() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 13)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        
        let entryId = UUID()
        let entry = ValueEntryModel(id: entryId, name: "Waffen , magische gegenstände, Mega Magische und Gegenstände Beutetabelle T", type: .text, value: "BeuteWaffen , nichtMagische GegenständeAlles, 5xBeutetabelle T, Beutetabelle A")
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , [Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC), Mega Magische und Gegenstände [Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7)")
        #expect(updatedEntry.value == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D)")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: true, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , [Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC), Mega Magische und Gegenstände Beutetabelle T")
        #expect(updatedEntry.value == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , nichtMagische GegenständeAlles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), Beutetabelle A")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: false, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , magische gegenstände, Mega Magische und Gegenstände [Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7)")
        #expect(updatedEntry.value == "Beute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7), [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D)")
    }
    
    @Test func scanValue() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 13)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        
        let entryId = UUID()
        let entry = ValueEntryModel(id: entryId, name: "6TalenteD20, Rüstung", type: .text, value: "Aktiver Kampf Wundersames ei, Adalbert Unheil, 6Talente")
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .value, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)D20, [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)")
        #expect(updatedEntry.value == "Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, 6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .value, caseInsensitive: true, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "6TalenteD20, Rüstung")
        #expect(updatedEntry.value == "Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, 6Talente")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .value, caseInsensitive: false, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)D20, [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)")
        #expect(updatedEntry.value == "Aktiver Kampf Wundersames ei, Adalbert Unheil, 6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)")
    }
    
    @Test func scanAll() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 13)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId).copy()

        let entryId = UUID()
        let entry = ValueEntryModel(id: entryId, name: "Waffen , magische gegenstände, Mega Magische und Gegenstände 4W20, Adalbert Unheil, D20,  Beutetabelle A 3W20xAxt, Beutetabelle T Fegel, 6TalenteD20, Rüstung5d20, Armbruste", type: .text, value: "4W20, Adalbert , nichtMagische GegenständeAlles, d20 Unheil, D20, 4W20xAxt, Fegel, Aktiver Kampf Wundersames ei, Adalbert Unheil, 6Talente4d20, d20ArmbrusteBeuteWaffen 5xBeutetabelle T,")
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        item.entries = [updatedEntry]
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]
        item.entries = [updatedEntry]
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .value, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]
        item.entries = [updatedEntry]
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)

        #expect(updatedEntry.name == "[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , [Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC), Mega Magische und Gegenstände [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E),  [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D) [3d20](RPG://DICE/0/AB7BA69C-E8BA-47F6-B183-013EA45834E0)xAxt, [Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7) Fegel, 6[Talente](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F)[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)5[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), Armbruste")
        #expect(updatedEntry.value == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A)xAxt, Fegel, Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, 6[Talente](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F)4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E)ArmbrusteBeute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7),")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .dice, caseInsensitive: true, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , [Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC), Mega Magische und Gegenstände [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E),  [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D) [3d20](RPG://DICE/0/AB7BA69C-E8BA-47F6-B183-013EA45834E0)xAxt, [Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7) Fegel, 6[Talente](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F)[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)5[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), Armbruste")
        #expect(updatedEntry.value == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A)xAxt, Fegel, Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, 6[Talente](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F)4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E)ArmbrusteBeute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7),")

        result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .table, caseInsensitive: false, words: true)
        #expect(result.count == 1)
        updatedEntry = result[0]
        #expect(updatedEntry.name == "[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) , [Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC), Mega Magische und Gegenstände [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E),  [Beutetabelle A](RPG://TABLES/0/31A67A30-3A5D-4FB9-ADC6-E7BC53F7877D) [3d20](RPG://DICE/0/AB7BA69C-E8BA-47F6-B183-013EA45834E0)xAxt, [Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7) Fegel, 6[Talente](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F)[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)5[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), Armbruste")
        #expect(updatedEntry.value == "[4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A), Adalbert , nicht[Magische Gegenstände](RPG://TABLES/0/0779AEEC-2FB8-4BBB-B08E-53BCF89EE3EC)Alles, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E) Unheil, [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [4d20](RPG://DICE/0/C7B7C9F1-BBD5-486B-849B-C99CF9EEB58A)xAxt, Fegel, Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, 6[Talente](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F)4[d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E), [d20](RPG://DICE/0/36F37F17-728D-4315-B2BB-B9401039D07E)ArmbrusteBeute[Waffen](RPG://TABLES/0/55E9FD60-A99E-4308-83E4-BCA0DF7DDF07) 5x[Beutetabelle T](RPG://TABLES/0/7F7512EA-29E4-427B-A4C9-300F75CDBDC7),")
    }
    
    @Test func scanValueEntries() async throws {
        let root = try await MockRoot.importTestData(ResourcesDebug.adventureTestData, itemCounter: 13)
        let sut = await root.editController(type: .main)

        let itemRowModel = await root.itemController.addNew(type: nil)
        
        let entryId = UUID()
        let entry = ValueEntryModel(id: entryId, name: "Waffen , Schlagen magische gegenstände, Mega Magische und Gegenstände 4W20, Adalbert Unheil, D20,  Beutetabelle A 3W20xAxt, Beutetabelle T Fegel, 6TalenteD20, Rüstung5d20, Armbruste", type: .text, value: "4W20, Adalbert , nichtMagische GegenständeAlles, d20 Unheil, D20, 4W20xAxt, Fegel, Aktiver Kampf Wundersames ei, Adalbert Unheil, Laufen 6Talente4d20, d20ArmbrusteBeuteWaffen 5xBeutetabelle T,")
        await sut.add(entry: entry, into: itemRowModel.itemId)
        
        var result = await sut.scan(itemId: itemRowModel.itemId, with: nil, module: .value, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        var updatedEntry = result[0]
        #expect(updatedEntry.name == "Waffen , Schlagen magische gegenstände, Mega Magische und Gegenstände 4W20, Adalbert Unheil, D20,  Beutetabelle A 3W20xAxt, Beutetabelle T Fegel, 6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)D20, [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)5d20, Armbruste")
        #expect(updatedEntry.value == "4W20, Adalbert , nichtMagische GegenständeAlles, d20 Unheil, D20, 4W20xAxt, Fegel, Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, Laufen 6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)4d20, d20ArmbrusteBeuteWaffen 5xBeutetabelle T,")

        let item = await root.itemController.itemOrEmpty(for: itemRowModel.itemId).copy()
        item.entries = [updatedEntry]
        await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)

        var scanId: UUID? = nil
        for itemId in await root.itemController.itemDataModel.items {
            if await root.itemController.itemOrEmpty(for: itemId).name == "Kampfwerte" {
                scanId = itemId
                break
            }
        }
        try #require(nil != scanId)

        result = await sut.scan(itemId: itemRowModel.itemId, with: [scanId!], module: .value, caseInsensitive: true, words: false)
        #expect(result.count == 1)
        updatedEntry = result[0]

        #expect(updatedEntry.name == "Waffen , [Schlagen](RPG://VALUES/0/16CE5408-ACF5-42A7-A5AD-CFC2D9A2F467/AA27A15D-7DC2-414D-ABF4-1895EE895E4E) magische gegenstände, Mega Magische und Gegenstände 4W20, Adalbert Unheil, D20,  Beutetabelle A 3W20xAxt, Beutetabelle T Fegel, 6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)D20, [Rüstung](RPG://VALUES/0/C40ECB8A-072B-4435-8958-6E6F152B2555)5d20, Armbruste")
        #expect(updatedEntry.value == "4W20, Adalbert , nichtMagische GegenständeAlles, d20 Unheil, D20, 4W20xAxt, Fegel, Aktiver Kampf [Wundersames Ei](RPG://VALUES/0/2FD1CFC6-DAAD-4631-BBCC-4D2F5962458C), Adalbert Unheil, [Laufen](RPG://VALUES/0/16CE5408-ACF5-42A7-A5AD-CFC2D9A2F467/7F60E84C-555D-4305-9017-C6880C44B699) 6[Talente](RPG://VALUES/0/06AD7B83-B829-440F-8A39-FD7BDBA8F00C)4d20, d20ArmbrusteBeuteWaffen 5xBeutetabelle T,")
    }

    @Test func addChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.editController(type: .main)

        let itemEntry = ValueEntryModel(id: UUID(), name: "Hansi", type: .text, value: "Hansi")
        let otherItemEntry = ValueEntryModel(id: UUID(), name: "Other Entry", type: .text, value: "Somthing")
        let item = ValueModel(id: UUID(), name: "Hansi", entries: [itemEntry, otherItemEntry])
        let subItem = ValueModel(id: UUID(), name: "Smaller Item", entries: [])

        await root.itemController.replace(model: item, isInsert: true, shouldRepairLinks: true)
        await root.itemController.replace(model: subItem, isInsert: true, shouldRepairLinks: true)
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .value))

        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId == nil)
        await #expect(sut.canAddChild(childId: subItem.id) == true)

        await sut.addChild(childId: subItem.id, into: itemEntry.id)
        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId != nil)
        await #expect(sut.canAddChild(childId: subItem.id) == false)
        await #expect(sut.model.entries[0].valueId == subItem.id)

        await sut.addChild(childId: subItem.id, into: itemEntry.id)
        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId != nil)
        await #expect(sut.canAddChild(childId: subItem.id) == false)
        await #expect(sut.model.entries[0].valueId == subItem.id)

        let otherSubItem = ValueModel(id: UUID(), name: "Smaller Item", entries: [])
        await root.itemController.replace(model: otherSubItem, isInsert: true, shouldRepairLinks: true)
        await #expect(root.itemController.itemOrEmpty(for: otherSubItem.id).parentId == nil)
        await #expect(sut.canAddChild(childId: otherSubItem.id) == true)

        await sut.addChild(childId: otherSubItem.id, into: otherItemEntry.id)
        await #expect(root.itemController.itemOrEmpty(for: otherSubItem.id).parentId != nil)
        await #expect(sut.canAddChild(childId: otherSubItem.id) == false)
        await #expect(sut.model.entries[1].valueId == otherSubItem.id)
        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId != nil)
        await #expect(sut.canAddChild(childId: subItem.id) == false)
        await #expect(sut.model.entries[0].valueId == subItem.id)

        await sut.removeChild(childId: otherSubItem.id)
        await #expect(root.itemController.itemOrEmpty(for: otherSubItem.id).parentId == nil)
        await #expect(sut.canAddChild(childId: otherSubItem.id) == true)
        await #expect(sut.model.entries[1].valueId == nil)

        await sut.addChild(childId: otherSubItem.id, into: itemEntry.id)
        await #expect(root.itemController.itemOrEmpty(for: otherSubItem.id).parentId != nil)
        await #expect(sut.canAddChild(childId: otherSubItem.id) == false)
        await #expect(sut.model.entries[0].valueId == otherSubItem.id)
        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId == nil)
        await #expect(sut.canAddChild(childId: subItem.id) == true)
    }

    @Test func removeChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.editController(type: .main)

        let itemEntry = ValueEntryModel(id: UUID(), name: "Hansi", type: .text, value: "Hansi")
        let otherItemEntry = ValueEntryModel(id: UUID(), name: "Other Entry", type: .text, value: "Somthing")
        let item = ValueModel(id: UUID(), name: "Hansi", entries: [itemEntry, otherItemEntry])
        let subItem = ValueModel(id: UUID(), name: "Smaller Item", entries: [])

        await root.itemController.replace(model: item, isInsert: true, shouldRepairLinks: true)
        await root.itemController.replace(model: subItem, isInsert: true, shouldRepairLinks: true)
        await sut.setCurrentItem(to: ItemRowTreeModel(itemId: item.id, typeId: .value))

        await sut.addChild(childId: subItem.id, into: itemEntry.id)
        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId != nil)
        await #expect(sut.canAddChild(childId: subItem.id) == false)
        await #expect(sut.model.entries[0].valueId == subItem.id)

        await sut.removeChild(childId:subItem.id)
        await #expect(root.itemController.itemOrEmpty(for: subItem.id).parentId == nil)
        await #expect(sut.canAddChild(childId: subItem.id) == true)
        await #expect(sut.model.entries[0].valueId == nil)
    }
}
#endif
