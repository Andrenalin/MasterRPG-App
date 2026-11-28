// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import DiceRPG
import Foundation
import AudioRPG
@testable import PdfRPG
import PhotoRPG
import TableRPG
@testable import CharacterRPG
import Testing

@testable import MapRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.exportController

        var ids = sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]!.isEmpty)

        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]! == [itemId])

        let newId = await root.itemController.addNew(type: .item)
        let entry = MapEntryModel(id: UUID(), name: "Nothing", content: root.linkController.generateLink(itemId: newId), coordinates: [])
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]!.count == 2)
    }

    @Test func exportingAllAfterDeletion() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.exportController
        let edit = root.editController

        let item = await edit.addNew(type: .item)
        let deleted = await edit.addNew(type: .item)
        try #require(item != nil)
        try #require(deleted != nil)
        edit.reset(name: "keep", itemId: item!.id, forceSave: false)
        edit.reset(name: "delete", itemId: deleted!.id, forceSave: false)

        await edit.delete(itemId: deleted!.id)

        let ids = sut.exportingAll()
        try #require(ids.ids[.map] != nil)
        #expect(ids.ids[.map]!.contains(item!.id))
        #expect(!ids.ids[.map]!.contains(deleted!.id))
        #expect(ids.ids[.map]!.count == 1)
    }

    @Test("A package for players holds the map only: a room's linked map is not exported")
    func exportingForPlayersSkipsLinks() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.exportController
        let mapId = await root.itemController.addNew(type: .item)
        let linkedMapId = await root.itemController.addNew(type: .item)
        let url = root.itemController.itemOrEmpty(for: linkedMapId).url(linkNumber: 0)
        root.itemController.itemOrEmpty(for: mapId).entries.append(
            MapEntryModel(id: UUID(), name: "Shown room", content: "\(url)", coordinates: [], isShown: true)
        )
        let seed = ItemModuleIds(ids: Set(arrayLiteral: mapId), module: .map)

        let owner = sut.exporting(itemIds: seed)
        let players = ExportAudience.$current.withValue(.players) { sut.exporting(itemIds: seed) }

        #expect(Set(owner.ids[.map] ?? []) == [mapId, linkedMapId])
        #expect(Set(players.ids[.map] ?? []) == [mapId])
    }

    @Test("The map data for players has no hidden pin and no hidden room name or text")
    func playerExportDataIsRedacted() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let mapId = await root.itemController.addNew(type: .item)
        let map = root.itemController.itemOrEmpty(for: mapId)
        map.entries = [
            // An unplaced pin sits in the first room (CODE_AUDIT_28 §5.6), so the shown room is first.
            MapEntryModel(id: UUID(), name: "Entrance hall", content: "Shown text", coordinates: [], isShown: true),
            MapEntryModel(id: UUID(), name: "Secret vault", content: "Hidden text", coordinates: [], isShown: false)
        ]
        map.mapPins = [
            MapPinModel(id: UUID(), name: "Hidden dragon", location: CGPoint(x: 7, y: 9), isShown: false),
            MapPinModel(id: UUID(), name: "Goblin", isShown: true)
        ]

        let data = try #require(try root.exportController.playerExportData(for: mapId))
        let text = String(decoding: data, as: UTF8.self)

        #expect(!text.contains("Secret vault"))
        #expect(!text.contains("Hidden text"))
        #expect(!text.contains("Hidden dragon"))
        #expect(text.contains("Entrance hall"))
        #expect(text.contains("Shown text"))
        #expect(text.contains("Goblin"))
        // The master's own item keeps everything.
        #expect(root.itemController.itemOrEmpty(for: mapId).mapPins.count == 2)
        #expect(root.itemController.itemOrEmpty(for: mapId).entries.last?.name == "Secret vault")
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let url = root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = MapEntryModel(id: UUID(), name: "Nothing", content: "\(url)", coordinates: [])
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .map))
        var mapIds = ids.ids[.map]
        try #require(mapIds != nil)
        #expect(mapIds!.count == 2)
        #expect(mapIds!.contains(itemId))
        #expect(mapIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .map))
        mapIds = ids.ids[.map]
        try #require(mapIds != nil)
        #expect(mapIds!.count == 2)
        #expect(mapIds!.contains(itemId))
        #expect(mapIds!.contains(newId))
        #expect(!mapIds!.contains(notConnected))
    }

    @Test func exportingMapIncludesCharacterAssociatedWithPin() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()
        let mapId = await root.itemController.addNew(type: .item)
        let characterId = await root.characterRoot.itemController.addNew(type: .item)
        let map = root.itemController.itemOrEmpty(for: mapId)
        map.mapPins = [
            MapPinModel(
                id: UUID(),
                name: "Associated character",
                characterId: characterId
            )
        ]

        // When
        let ids = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: Set([mapId]), module: .map)
        )

        // Then
        #expect(ids.ids[.value]?.contains(characterId) == true)
    }

    @Test func gameMapExportIncludesLinkedPdfButExcludesCharacterPackages() async throws {
        // Given
        let root = try await MockRoot.importTestData()
        await root.itemController.resetData()
        let mapId = await root.itemController.addNew(type: .item)
        let pdfId = await root.pdfRoot.itemControllable.addNew(type: .item)
        let linkedCharacterId = await root.characterRoot.itemController.addNew(type: .item)
        let pinnedCharacterId = await root.characterRoot.itemController.addNew(type: .item)
        let sessionCharacterId = await root.characterRoot.itemController.addNew(type: .item)
        let pdfLink = root.pdfRoot.linkControllable.generateLink(itemId: pdfId)
        let characterLink = root.characterRoot.linkControllable.generateLink(itemId: linkedCharacterId)
        let map = root.itemController.itemOrEmpty(for: mapId)
        map.entries = [
            MapEntryModel(
                id: UUID(),
                name: "Dependencies",
                content: "\(pdfLink) \(characterLink)",
                coordinates: []
            )
        ]
        map.mapPins = [
            MapPinModel(
                id: UUID(),
                name: "Pinned Character",
                characterId: pinnedCharacterId
            )
        ]
        root.gameController.mapGameModel.playerPins = [
            MapPinModel(
                id: UUID(),
                name: "Session-only Character",
                characterId: sessionCharacterId,
                isPlayer: true
            )
        ]
        root.itemController.itemDataModel.resetGame(start: true)

        // When
        let ids = root.exportController.exporting(
            itemIds: ItemModuleIds(ids: Set([mapId]), module: .map)
        )

        // Then
        #expect(ids.ids[.pdf]?.contains(pdfId) == true)
        #expect(ids.ids[.value, default: []].isEmpty)
        #expect(ids.ids[.value]?.contains(linkedCharacterId) != true)
        #expect(ids.ids[.value]?.contains(pinnedCharacterId) != true)
        #expect(ids.ids[.value]?.contains(sessionCharacterId) != true)
    }
}
#endif
