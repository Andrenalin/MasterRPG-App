// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

@MainActor
struct LinkRegisterControllerTests {
    func setUp() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let _ = root.editController.linkRegisterController
        return root
    }

    @Test func outgoingLinksAreLookedUpByExactSourceEntry() {
        // Given
        let sut = LinkRegisterController(root: nil)
        let itemId = UUID()
        let firstSource = ItemRowModel(itemId: itemId, entryId: UUID(), typeId: .value)
        let secondSource = ItemRowModel(itemId: itemId, entryId: UUID(), typeId: .value)
        let firstLink = LinkRegisterModel(
            name: "First",
            source: firstSource,
            destination: ItemRowModel(itemId: UUID(), typeId: .photo)
        )
        let secondLink = LinkRegisterModel(
            name: "Second",
            source: secondSource,
            destination: ItemRowModel(itemId: UUID(), typeId: .dice)
        )

        // When
        sut.register(links: [firstLink, secondLink])

        // Then
        #expect(sut.linksFrom(source: firstSource) == [firstLink])
        #expect(sut.linksFrom(source: secondSource) == [secondLink])
        #expect(sut.isUsed(link: firstLink.destination))
        #expect(sut.isUsed(link: secondLink.destination))
    }

    @Test func addModelWithLinks() async throws {
        let root = try await setUp()
        let sut = root.editController.linkRegisterController

        let diceId = UUID()
        let diceLink = root.diceRoot.linkControllable.generateLink(itemId: diceId)
        let photoId = UUID()
        let photoLink = root.photoRoot.linkControllable.generateLink(itemId: photoId)
        let item = await root.editController.addNew(type: .item)
        try #require(item != nil)
        
        #expect(sut.model.items.count == 17)
        let itemId = item!.id
        let entryId = UUID()
        let model = ValueModel(id: itemId, name: "Super", description: "Nix", entries: [ValueEntryModel(id: entryId, name: "Good \(photoLink)", type: .text, value: diceLink)])
        root.editController.save(updated: model, message: "Test", forceSave: false)

        #expect(sut.model.items.count == 19)
        var itemLinks = sut.model.items[diceId]
        try #require(nil != itemLinks)
        #expect(itemLinks!.count == 1)
        #expect(itemLinks![0].source == ItemRowModel(itemId: itemId, entryId: entryId, typeId: .value))

        var itemLinks2 = sut.model.items[photoId]
        #expect(nil != itemLinks2)
        #expect(itemLinks2!.count == 1)
        #expect(itemLinks2![0].source == ItemRowModel(itemId: itemId, entryId: entryId, typeId: .value))

        root.itemController.replace(model: model, isInsert: false)

        itemLinks = sut.model.items[diceId]
        #expect(nil != itemLinks)
        #expect(itemLinks!.count == 1)
        #expect(itemLinks![0].source == ItemRowModel(itemId: itemId, entryId: entryId, typeId: .value))

        itemLinks2 = sut.model.items[photoId]
        #expect(nil != itemLinks2)
        #expect(itemLinks2!.count == 1)
        #expect(itemLinks2![0].source == ItemRowModel(itemId: itemId, entryId: entryId, typeId: .value))
        
        try await isUsed()
    }

    func isUsed() async throws {
        let root = try await setUp()
        let sut = root.editController.linkRegisterController

        let diceId = UUID()
        let diceLink = root.diceRoot.linkControllable.generateLink(itemId: diceId)
        let photoId = UUID()
        let photoLink = root.photoRoot.linkControllable.generateLink(itemId: photoId)
        let itemId = UUID()
        let entryId = UUID()

        #expect(sut.isUsed(link: ItemRowModel(itemId: diceId, typeId: .dice)) == false)
        #expect(sut.isUsed(link: ItemRowModel(itemId: photoId, typeId: .photo)) == false)

        let model = ValueModel(id: itemId, name: "Super", description: "Nix", entries: [ValueEntryModel(id: entryId, name: "Good \(photoLink)", type: .text, value: diceLink)])
        root.editController.save(updated: model, message: "Test", forceSave: false)

        #expect(sut.isUsed(link: ItemRowModel(itemId: diceId, typeId: .dice)))
        #expect(sut.isUsed(link: ItemRowModel(itemId: photoId, typeId: .photo)))
    }
}
#endif
