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

struct LinkRegisterControllerTests {
    func setUp() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController.linkRegisterController
        await sut.reset()
        return root
    }

    @Test func addModelWithLinks() async throws {
        let root = try await setUp()
        let sut = root.editController.linkRegisterController

        let diceId = UUID()
        let diceLink = await root.diceRoot.linkControllable.generateLink(itemId: diceId)
        let photoId = UUID()
        let photoLink = await root.photoRoot.linkControllable.generateLink(itemId: photoId)
        let itemID = UUID()
        let entryID = UUID()
        let model = ValueModel(id: itemID, name: "Super", description: "Nix", entries: [ValueEntryModel(id: entryID, name: "Good \(photoLink)", type: .text, value: diceLink)])
        await root.itemController.replace(model: model, isInsert: true)
        
        //await #expect(sut.model.entries.count == 0)
        await #expect(sut.model.items.count == 2)
        var itemLinks = await sut.model.items[diceId]
        try #require(nil != itemLinks)
        #expect(itemLinks!.count == 1)
        #expect(itemLinks![0].source == ItemRowModel(itemId: itemID, entryId: entryID, typeId: .value))

        var itemLinks2 = await sut.model.items[photoId]
        #expect(nil != itemLinks2)
        #expect(itemLinks2!.count == 1)
        #expect(itemLinks2![0].source == ItemRowModel(itemId: itemID, entryId: entryID, typeId: .value))

        await root.itemController.replace(model: model, isInsert: false)

        itemLinks = await sut.model.items[diceId]
        #expect(nil != itemLinks)
        #expect(itemLinks!.count == 1)
        #expect(itemLinks![0].source == ItemRowModel(itemId: itemID, entryId: entryID, typeId: .value))

        itemLinks2 = await sut.model.items[photoId]
        #expect(nil != itemLinks2)
        #expect(itemLinks2!.count == 1)
        #expect(itemLinks2![0].source == ItemRowModel(itemId: itemID, entryId: entryID, typeId: .value))
        
        try await isUsed()
    }

    func isUsed() async throws {
        let root = try await setUp()
        let sut = root.editController.linkRegisterController

        let diceId = UUID()
        let diceLink = await root.diceRoot.linkControllable.generateLink(itemId: diceId)
        let photoId = UUID()
        let photoLink = await root.photoRoot.linkControllable.generateLink(itemId: photoId)
        let itemID = UUID()
        let entryID = UUID()

        #expect(await sut.isUsed(link: ItemRowModel(itemId: diceId, typeId: .dice)) == false)
        #expect(await sut.isUsed(link: ItemRowModel(itemId: photoId, typeId: .photo)) == false)

        let model = ValueModel(id: itemID, name: "Super", description: "Nix", entries: [ValueEntryModel(id: entryID, name: "Good \(photoLink)", type: .text, value: diceLink)])
        await root.itemController.replace(model: model, isInsert: true)

        #expect(await sut.isUsed(link: ItemRowModel(itemId: diceId, typeId: .dice)))
        #expect(await sut.isUsed(link: ItemRowModel(itemId: photoId, typeId: .photo)))
    }
}
#endif
