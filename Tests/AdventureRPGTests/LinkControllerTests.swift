// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import AudioRPG
@testable import CharacterRPG
@testable import DiceRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import SpaceRPG
@testable import TableRPG
@testable import WeatherRPG

@MainActor
struct LinkControllerTests {
    private func makeRoot() -> AdventureRootModel {
        let audioRoot = AudioRootModel.testRoot()
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let spaceRoot = SpaceRootModel.testRoot()
        let weatherRoot = WeatherRootModel.testRoot(photoRoot: photoRoot)
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let characterRoot = CharacterRootModel.testRoot(
            diceRoot: diceRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            tableRoot: tableRoot
        )
        let mapRoot = MapRootModel.testRoot(
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            tableRoot: tableRoot,
            characterRoot: characterRoot
        )
        let root = AdventureRootModel.testRoot(
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            characterRoot: characterRoot,
            weatherRoot: weatherRoot
        )
        root.setUp(
            root: RootManager(
                adventureRoot: root,
                audioRoot: audioRoot,
                characterRoot: characterRoot,
                diceRoot: diceRoot,
                generatorRoot: root,
                mapRoot: mapRoot,
                pdfRoot: pdfRoot,
                photoRoot: photoRoot,
                spaceRoot: spaceRoot,
                tableRoot: tableRoot,
                weatherRoot: weatherRoot
            ),
            context: nil
        )
        return root
    }

    @Test func validateLinksWithLinkReplace() async throws {
        let root = try await MockRoot.importTestData()

        let sut = root.linkController

        let photoId = UUID()
        let photo = PhotoModel(id: photoId, name: "Photo", description: "Some Text", tags: ["Some"], category: .adventure)
        root.photoRoot.editController.save(updated: photo, message: "Test", forceSave: false)
        
        let tableEntryId = UUID()
        let tableEntry = TableEntryModel(id: tableEntryId, name: "Table", content: "Some Text")
        let tableId = UUID()
        let table = TableModel(id: tableId, name: "Table", description: "Some Text", tags: ["Some"], category: .rules, entries: [tableEntry])
        root.tableRoot.editController.save(updated: table, message: "Test", forceSave: false)
        
        let valueEntryId = UUID()
        let valueEntry = ValueEntryModel(id: valueEntryId, name: "Value", type: .text, value: "Some Text")
        let valueId = UUID()
        let value = ValueModel(id: valueId, name: "Value", description: "Some Text", tags: ["Some"], category: .rules, entries: [valueEntry])
        root.characterRoot.editController.save(updated: value, message: "Test", forceSave: false)
        
        var content = "Link to Photo "
        content = root.photoRoot.linkControllable.generateLinks(itemId: photoId, entryId: nil, into: content)
        let entry1 = AdventureEntryModel(id: UUID(), name: "Hello", content: content)
        
        content = root.tableRoot.linkControllable.generateLinks(itemId: tableId, entryId: tableEntryId, into: content)
        let entry2 = AdventureEntryModel(id: UUID(), name: "Hello 2", content: content)

        content = root.characterRoot.linkControllable.generateLinks(itemId: valueId, entryId: valueEntryId, into: content)
        let entry3 = AdventureEntryModel(id: UUID(), name: "Hello 3", content: content)
        
        let itemId = UUID()
        let item = AdventureModel(id: itemId, name: "Name", description: "Some Text", tags: ["Some"], category: .scenario, photoId: photoId, entries: [entry1, entry2, entry3])
        root.editController.save(updated: item, message: "Test", forceSave: false)
        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id] == entry2)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id] == entry3)
        
        await sut.validateLinks(reportModel: ValidateRepairModel())
        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id] == entry2)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id] == entry3)

        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: photoId, typeId: .photo)).count == 4)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, typeId: .table)).count == 2)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, entryId: tableEntryId, typeId: .table)).count == 2)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, typeId: .value)).count == 1)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, entryId: valueEntryId, typeId: .value)).count == 1)

        await root.characterRoot.itemController.delete(itemId: valueId)

        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, typeId: .value)).count == 1)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: valueId, entryId: valueEntryId, typeId: .value)).count == 1)

        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry2.id] == entry2)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry3.id] == entry3)

        root.tableRoot.editController.setCurrentItem(to: ItemRowTreeModel(itemId: tableId, typeId: .table))
        root.tableRoot.editController.remove(itemId: tableId, entryId: tableEntryId, forceSave: false)
        
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, typeId: .table)).count == 2)
        #expect(root.linkRegisterController.used(for: ItemRowModel(itemId: tableId, entryId: tableEntryId, typeId: .table)).count == 2)

        #expect(root.itemController.itemOrEmpty(for: itemId).photoId == photoId)
        #expect(root.itemController.itemOrEmpty(for: itemId)[entry1.id] == entry1)
    }

    @Test func handleTextLinkRoutesAndToggleLinkDelegates() {
        let root = makeRoot()
        let adventureEntry = AdventureEntryModel(id: UUID(), name: "Scene", content: "Scene content")
        let adventure = AdventureModel(
            id: UUID(),
            name: "Adventure Link",
            description: "Adventure description",
            entries: [adventureEntry]
        )
        let map = MapModel(id: UUID(), name: "Map Link", description: "Map description")
        root.itemController.replace(model: adventure, isInsert: true)
        root.mapRoot.itemController.replace(model: map, isInsert: true)

        let adventureText = root.linkController.generateLinks(itemId: adventure.id, entryId: nil, into: "See ")
        let adventureUrl = URL(string: root.linkController.generateLinkAdr(linkNumber: 0, itemId: adventure.id, entryId: nil))!
        let handledAdventure = root.linkController.handleTextLink(
            url: adventureUrl,
            in: adventureText,
            shareResult: nil,
            toggler: nil,
            editAction: { row in row.itemId == adventure.id }
        )

        let mapText = root.mapRoot.linkControllable.generateLinks(itemId: map.id, entryId: nil, into: "Map ")
        let mapUrl = URL(string: root.mapRoot.linkControllable.generateLinkAdr(linkNumber: 0, itemId: map.id, entryId: nil))!
        let handledMap = root.linkController.handleTextLink(
            url: mapUrl,
            in: mapText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )

        let unchanged = root.linkController.handleTextLink(
            url: URL(string: "https://example.com")!,
            in: "Plain text",
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )

        #expect(handledAdventure.localizedStandardContains("Adventure description"))
        #expect(handledAdventure.localizedStandardContains("Remove"))
        #expect(handledMap.localizedStandardContains("Map description"))
        #expect(unchanged == "Plain text")
        #expect(root.linkController.toggleLink(module: .map, linkNumber: 0, itemId: map.id, entryId: nil, command: nil) == "Map description")
        #expect(root.linkController.toggleLink(module: .adventure, linkNumber: 0, itemId: adventure.id, entryId: adventureEntry.id, command: nil) == "Scene content")

        _ = root.linkController.toggleLink(module: .audio, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .dice, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .pdf, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .photo, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .space, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .table, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .value, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
        _ = root.linkController.toggleLink(module: .weather, linkNumber: 0, itemId: UUID(), entryId: nil, command: nil)
    }

    @Test func toggleTextLinkCommandsExpandAndRemoveAdventureLinks() {
        let root = makeRoot()
        let adventure = AdventureModel(
            id: UUID(),
            name: "Command Adventure",
            description: "Command description",
            entries: [
                AdventureEntryModel(id: UUID(), name: "Entry", content: "Entry description")
            ]
        )
        root.itemController.replace(model: adventure, isInsert: true)
        let entryId = adventure.entries[0].id
        let itemText = root.linkController.generateLinks(itemId: adventure.id, entryId: nil, into: "See ")
        let entryText = root.linkController.generateLinks(itemId: adventure.id, entryId: entryId, into: "Open ")

        let expandedItem = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: adventure.id,
            entryId: nil,
            command: nil,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: { row in row.itemId == adventure.id }
        )
        let expandedEntry = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: adventure.id,
            entryId: entryId,
            command: nil,
            in: entryText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let removedItem = root.linkController.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition,
            itemId: adventure.id,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let showCommand = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: adventure.id,
            entryId: nil,
            command: LinkType.show.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )

        #expect(expandedItem.localizedStandardContains("Command description"))
        #expect(expandedItem.localizedStandardContains("Remove"))
        #expect(expandedEntry.localizedStandardContains("Entry description"))
        #expect(removedItem.localizedStandardContains("Command Adventure"))
        #expect(showCommand == itemText)
    }

    @Test func repairLinksAndValidateLinksHandleMissingPhotoReferences() async throws {
        let root = makeRoot()
        let oldPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        root.photoRoot.editController.reset(name: "Portrait", itemId: oldPhotoId, forceSave: false)
        let content = root.photoRoot.linkControllable.generateLinks(itemId: oldPhotoId, entryId: nil, into: "Look ")
        let links = LinkReplaceController.links(for: content)

        root.photoRoot.itemController.itemDataModel.items.removeAll { $0 == oldPhotoId }
        root.photoRoot.itemController.itemDataModel.itemData[oldPhotoId] = nil

        let newPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        root.photoRoot.editController.reset(name: "Portrait", itemId: newPhotoId, forceSave: false)

        let repaired = root.linkController.repairLinks(links, in: content)

        #expect(repaired.localizedStandardContains(newPhotoId.uuidString))
        #expect(!repaired.localizedStandardContains(oldPhotoId.uuidString))

        let adventureId = await root.itemController.addNew(type: .scenario)
        let adventure = try #require(root.itemController.itemSync(for: adventureId))
        adventure.photoId = UUID()

        root.linkController.validateLinks(on: adventureId)

        #expect(root.itemController.itemSync(for: adventureId)?.photoId == nil)
    }

    @Test func collectLinksWalksPhotoMapWeatherAndNestedAdventureLinks() async {
        let root = makeRoot()
        let adventurePhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let entryPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let mapPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let weatherPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let nestedAdventurePhotoId = await root.photoRoot.itemController.addNew(type: .item)

        let mapId = await root.mapRoot.itemController.addNew(type: .item)
        root.mapRoot.editController.add(photoId: mapPhotoId, itemId: mapId)

        let weatherId = await root.weatherRoot.itemController.addNew(type: .scenario)
        root.weatherRoot.editController.add(photoId: weatherPhotoId, itemId: weatherId, forceSave: false)

        let nestedAdventure = AdventureModel(
            id: UUID(),
            name: "Nested Adventure",
            photoId: nestedAdventurePhotoId
        )
        root.itemController.replace(model: nestedAdventure, isInsert: true)

        var content = root.photoRoot.linkControllable.generateLinks(itemId: entryPhotoId, entryId: nil, into: "Entry ")
        content = root.mapRoot.linkControllable.generateLinks(itemId: mapId, entryId: nil, into: content)
        content = root.weatherRoot.linkControllable.generateLinks(itemId: weatherId, entryId: nil, into: content)
        content = root.linkController.generateLinks(itemId: nestedAdventure.id, entryId: nil, into: content)

        let adventure = AdventureModel(
            id: UUID(),
            name: "Collecting Adventure",
            photoId: adventurePhotoId,
            entries: [
                AdventureEntryModel(id: UUID(), name: "Links", content: content)
            ]
        )
        root.itemController.replace(model: adventure, isInsert: true)

        let collected = Set(root.linkController.collectLinks(of: .photo, from: adventure.id))

        #expect(collected == Set([
            adventurePhotoId,
            entryPhotoId,
            mapPhotoId,
            weatherPhotoId,
            nestedAdventurePhotoId
        ]))
        #expect(root.linkController.collectLinks(of: .photo, from: UUID()).isEmpty)
    }
}
