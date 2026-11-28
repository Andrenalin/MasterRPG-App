// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
import MapRPG
import PdfRPG
import SpaceRPG
import CharacterRPG
import RPGResourcesDebug
import Testing
import WeatherRPG

@testable import AdventureRPG
@testable import PhotoRPG
@testable import TableRPG

@MainActor
struct ItemControllerTests {
    @Test func itemRegisterLinks() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.itemController

        #expect(sut.itemDataModel.items.count == 3)
        #expect(root.photoRoot.itemController.itemDataModel.items.count == 27)
        let model = sut.itemOrEmpty(for: sut.itemDataModel.items[0])
        #expect(model.name == "1. Kinder der Ratten")
        let photoId = model.photoId
        #expect(nil != photoId)
        #expect(root.photoRoot.itemController.itemOrEmpty(for: photoId!).name == "Ratten")
        let changed = model.copy()
        changed.name = "Updated"
        let newId = UUID()
        changed.photoId = newId
        root.editController.save(updated: changed, message: "", forceSave: false)
        let isUsed = sut.linkRegisterController.isUsed(link: ItemRowModel(itemId: newId, typeId: .photo))
        #expect(isUsed)

        let affectedLinks = sut.linkRegisterController.used(for: ItemRowModel(itemId: newId, typeId: .photo))
        try #require(affectedLinks.count == 1)
        #expect(affectedLinks[0].module == .adventure)
        #expect(affectedLinks[0].name == model.name)
    }

    @Test func itemRegisterLinksIsUsedReturnsAlsoEntries() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.itemController

        let photoId = UUID()
        let photo = PhotoModel(id: photoId, name: "Referenced Photo")
        root.photoRoot.editController.save(updated: photo, message: "Test", forceSave: false)

        let content = root.photoRoot.linkControllable.generateLinks(
            itemId: photoId,
            entryId: nil,
            into: "Entry link: "
        )
        let entry = AdventureEntryModel(id: UUID(), name: "Linked Entry", content: content)
        let item = AdventureModel(
            id: UUID(),
            name: "Link Sources",
            photoId: photoId,
            entries: [entry]
        )
        root.editController.save(updated: item, message: "Test", forceSave: false)

        // Re-registering the item's links must remain idempotent.
        sut.linkRegisterController.register(links: item.linkRegisterModels)

        let photoRow = ItemRowModel(itemId: photoId, typeId: .photo)
        let isUsed = sut.linkRegisterController.isUsed(link: photoRow)
        #expect(isUsed)
        let affectedLinks = sut.linkRegisterController.used(for: photoRow)
        #expect(affectedLinks.count == 2)
        #expect(affectedLinks.contains { $0.entryName == nil })
        #expect(affectedLinks.contains { $0.entryName == entry.name })
    }
}
