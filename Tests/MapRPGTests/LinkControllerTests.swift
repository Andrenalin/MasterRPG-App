// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AudioRPG
@testable import CharacterRPG
@testable import DiceRPG
@testable import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
@testable import TableRPG

@MainActor
struct LinkControllerTests {

    private func makeRoot() -> MapRootModel {
        let audioRoot = AudioRootModel.testRoot()
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        let characterRoot = CharacterRootModel.testRoot(
            diceRoot: diceRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            tableRoot: tableRoot
        )
        return MapRootModel.testRoot(
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            tableRoot: tableRoot,
            characterRoot: characterRoot
        )
    }

    @Test func quickLinksAreSortedByReferenceLength() async {
        let root = makeRoot()
        let shortId = await root.itemController.addNew(type: .item)
        let longId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Crypt", itemId: shortId)
        root.editController.reset(name: "Ancient Underground Reservoir", itemId: longId)

        let entryA = MapEntryModel(id: UUID(), name: "Hall", content: "A", coordinates: [])
        let entryB = MapEntryModel(id: UUID(), name: "Collapsed Southern Gallery", content: "B", coordinates: [])
        root.editController.add(entry: entryA, into: longId)
        root.editController.add(entry: entryB, into: longId)

        let itemLinks = root.linkController.link(for: .map)
        let entryLinks = root.linkController.linkEntries(for: longId)

        #expect(itemLinks.map(\.reference).prefix(2) == ["Ancient Underground Reservoir", "Crypt"])
        #expect(entryLinks.map(\.reference) == ["Collapsed Southern Gallery", "Hall"])
        #expect(itemLinks.first?.markdownUrl.localizedStandardContains(longId.uuidString) == true)
        #expect(entryLinks.first?.markdownUrl.localizedStandardContains(entryB.id.uuidString) == true)
    }

    @Test func toggleTextLinkExpandsEntriesAndCommands() async {
        let root = makeRoot()
        let entryId = UUID()
        let map = MapModel(
            id: UUID(),
            name: "Vault Map",
            description: "Hidden passage",
            entries: [
                MapEntryModel(id: entryId, name: "Vault", content: "Entry contents", coordinates: [])
            ]
        )
        root.itemController.replace(model: map, isInsert: true)

        let itemText = root.linkController.generateLinks(itemId: map.id, entryId: nil, into: "See ")
        let expandedItem = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: map.id,
            entryId: nil,
            command: nil,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: { row in row.itemId == map.id }
        )

        let entryText = root.linkController.generateLinks(itemId: map.id, entryId: entryId, into: "Open ")
        let expandedEntry = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: map.id,
            entryId: entryId,
            command: nil,
            in: entryText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )

        let removedItem = root.linkController.toggleTextLink(
            linkNumber: LinkType.remove.linkNumberAddition,
            itemId: map.id,
            entryId: nil,
            command: LinkType.remove.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let showCommand = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: map.id,
            entryId: nil,
            command: LinkType.show.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )
        let shareCommand = root.linkController.toggleTextLink(
            linkNumber: 0,
            itemId: map.id,
            entryId: nil,
            command: LinkType.share.rawValue,
            in: itemText,
            shareResult: nil,
            toggler: nil,
            editAction: nil
        )

        #expect(expandedItem.localizedStandardContains("Hidden passage"))
        #expect(expandedItem.localizedStandardContains("Remove"))
        #expect(expandedEntry.localizedStandardContains("Entry contents"))
        #expect(removedItem.localizedStandardContains("Vault Map"))
        #expect(showCommand == itemText)
        #expect(shareCommand == itemText)
    }

    @Test func repairLinksDelegatesToPhotoRoot() async {
        let root = makeRoot()
        let oldPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        root.photoRoot.editController.reset(name: "Portrait", itemId: oldPhotoId)
        let content = root.photoRoot.linkControllable.generateLinks(itemId: oldPhotoId, entryId: nil, into: "Look ")
        let links = LinkReplaceController.links(for: content)

        root.photoRoot.itemController.itemDataModel.items.removeAll { $0 == oldPhotoId }
        root.photoRoot.itemController.itemDataModel.itemData[oldPhotoId] = nil

        let newPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        root.photoRoot.editController.reset(name: "Portrait", itemId: newPhotoId)

        let repaired = root.linkController.repairLinks(links, in: content)

        #expect(repaired.localizedStandardContains(newPhotoId.uuidString))
        #expect(!repaired.localizedStandardContains(oldPhotoId.uuidString))
    }

    @Test func validateLinksClearsMissingPhotoAndKeepsExistingPhoto() async throws {
        let root = makeRoot()
        let missingPhotoMapId = await root.itemController.addNew(type: .item)
        let missingPhotoMap = try #require(root.itemController.itemSync(for: missingPhotoMapId))
        missingPhotoMap.photoId = UUID()

        root.linkController.validateLinks(on: missingPhotoMapId)

        #expect(root.itemController.itemSync(for: missingPhotoMapId)?.photoId == nil)

        let photoId = await root.photoRoot.itemController.addNew(type: .item)
        let validPhotoMapId = await root.itemController.addNew(type: .item)
        let validPhotoMap = try #require(root.itemController.itemSync(for: validPhotoMapId))
        validPhotoMap.photoId = photoId

        root.linkController.validateLinks(on: validPhotoMapId)

        #expect(root.itemController.itemSync(for: validPhotoMapId)?.photoId == photoId)
    }

    @Test func collectLinksReturnsMapPhotoEntryPhotoAndPinPhoto() async {
        let root = makeRoot()
        let mapPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let entryPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let pinPhotoId = await root.photoRoot.itemController.addNew(type: .item)
        let entryContent = root.photoRoot.linkControllable.generateLinks(itemId: entryPhotoId, entryId: nil, into: "Entry ")
        let map = MapModel(
            id: UUID(),
            name: "Linked Map",
            entries: [
                MapEntryModel(id: UUID(), name: "Room", content: entryContent, coordinates: [])
            ],
            photoId: mapPhotoId,
            mapPins: [
                MapPinModel(id: UUID(), name: "Marker", photoId: pinPhotoId)
            ]
        )
        root.itemController.replace(model: map, isInsert: true)

        let collected = Set(root.linkController.collectLinks(of: .photo, from: map.id))

        #expect(collected == Set([mapPhotoId, entryPhotoId, pinPhotoId]))
        #expect(root.linkController.collectLinks(of: .photo, from: UUID()).isEmpty)
    }
}
#endif
