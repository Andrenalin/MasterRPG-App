// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import SwiftUI
import Testing

@testable import CharacterRPG
@testable import MapRPG

@MainActor
struct EditControllerTests {
    @Test func addEntry() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = root.itemController.itemDataModel.items[0]
        let item = root.itemController.itemOrEmpty(for: itemId)
        
        let sut = root.editController
        sut.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .map))
        
        let entries = item.entries
        #expect(item.entries.count == 13)

        let modifiedMap = item.copy()
        let isHex = sut.toggleHexMap(for: modifiedMap)
        #expect(isHex)
        #expect(sut.editEntries(for: item).count == 13)
        #expect(sut.editEntries(for: item) == entries)
        #expect(item.entries.count == 13)

        let entryId = UUID()
        let entry = MapEntryModel(id: entryId, name: "Name Eingang", content: "Was ist in 7a", coordinates: [])
        sut.add(entry: entry, into: item.id)

        #expect(item.entries.count == 14)
        #expect(item.entries[13].id == entryId)
        #expect(item.entries[13].name == "Name Eingang")
        #expect(item.entries[13].content == "Was ist in 7a")
    }

    @Test func editControllerRoutesAndLinkRules() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let itemId = await root.itemController.addNew(type: .item)
        let entryId = UUID()
        let sut = root.editController
        let row = ItemRowModel(itemId: itemId, entryId: entryId, typeId: .map)

        #expect(sut.linkModules == [.audio, .value, .dice, .map, .pdf, .photo, .table])
        #expect(sut.canAddLink(module: .audio, entryId: entryId))
        #expect(sut.canAddLink(module: .dice, entryId: nil))
        #expect(sut.canAddLink(module: .value, entryId: nil))
        #expect(sut.canAddLink(module: .table, entryId: nil))
        #expect(!sut.canAddLink(module: .value, entryId: entryId))
        #expect(!sut.canAddLink(module: .table, entryId: entryId))
        #expect(!sut.canAddLink(module: .weather, entryId: nil))

        let linkRoute = try #require(sut.linkSelectionDestination(itemRowModel: row) as? MapEditorRoute)
        let quickRoute = try #require(sut.quickEditorDestination(itemRowModel: row) as? MapEditorRoute)

        #expect(linkRoute == .linkSelection(row))
        #expect(quickRoute == .quickEditor(itemId))
        #expect(sut.thumbnailEntryViewType == .photo)
        #expect(sut.additionalEntryViewType == .custom)
        #expect(sut.create(name: "Hall", content: "North").name == "Hall")
        _ = sut.fileUrlDataController
        _ = sut.additionalRowView(for: row, entry: MapEntryModel.empty(entryId), textModel: nil)
    }

    @Test func resetDisplayPropertiesAndPhoto() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let itemId = await root.itemController.addNew(type: .item)
        let item = root.itemController.itemOrEmpty(for: itemId)
        let sut = root.editController
        let photoId = UUID()
        let tileCoordinates = [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]

        sut.add(photoId: photoId, itemId: itemId)
        sut.reset(borderThickness: 7, itemId: itemId)
        sut.reset(hasBorder: false, itemId: itemId)
        sut.reset(hasBorder: true, itemId: itemId)
        sut.reset(borderColor: .blue, itemId: itemId)
        sut.reset(coverColor: .green, itemId: itemId)
        sut.reset(tileCoordinates: tileCoordinates, itemId: itemId)

        #expect(item.photoId == photoId)
        #expect(item.displayConfig.borderThickness == 4)
        #expect(item.displayConfig.hasBorder)
        #expect(item.displayConfig.border.color == .blue)
        #expect(item.displayConfig.color == .green)
        #expect(item.displayConfig.tileCoordinates == tileCoordinates)
    }

    @Test func pinsAndMonsterPlacementUseValidatedLocations() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let model = MapModel(id: UUID(), name: "Arena")
        let firstPin = MapPinModel(id: UUID(), name: "First")
        let secondPin = MapPinModel(id: UUID(), name: "Second")
        let thirdPin = MapPinModel(id: UUID(), name: "Third")

        sut.add(pin: firstPin, at: -3, to: model)
        sut.add(pin: secondPin, at: 99, to: model)
        sut.add(pin: thirdPin, to: model)

        #expect(model.mapPins.map(\.id) == [firstPin.id, secondPin.id, thirdPin.id])

        let roomEntry = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 80),
                CGPoint(x: 0, y: 80)
            ]
        )
        let monsterMap = MapModel(id: UUID(), name: "Monster Room", entries: [roomEntry], pinScale: 1)
        let valueId = await root.characterRoot.itemController.addNew(type: .item)
        root.characterRoot.editController.reset(name: "Sentinel", itemId: valueId)

        sut.addMonsters(
            map: monsterMap,
            entryId: roomEntry.id,
            location: nil,
            monsters: [ItemRowModel(itemId: valueId, typeId: .value)],
            number: 2
        )

        #expect(monsterMap.mapPins.count == 2)
        #expect(monsterMap.mapPins.allSatisfy { $0.name == "Sentinel" })
        #expect(monsterMap.mapPins.allSatisfy { $0.characterId == valueId })
        #expect(monsterMap.mapPins.map(\.location) == [CGPoint(x: 25, y: 40), CGPoint(x: 74, y: 89)])
    }

    @Test func mergeAndReplaceEntriesUpdateExistingMapData() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let keepId = UUID()
        let removeId = UUID()
        let newId = UUID()
        let map = MapModel(
            id: UUID(),
            name: "Merge Map",
            entries: [
                MapEntryModel(id: keepId, name: "Keep", content: "old", coordinates: []),
                MapEntryModel(id: removeId, name: "Recover", content: "saved", coordinates: [])
            ]
        )
        root.itemController.replace(model: map, isInsert: true)

        let incoming = [
            MapEntryModel(id: UUID(), name: "Keep", content: "updated", coordinates: []),
            MapEntryModel(id: newId, name: "New", content: "fresh", coordinates: [])
        ]
        let preview = sut.merge(itemId: map.id, entries: incoming)

        #expect(preview.map(\.id) == [keepId, newId])
        #expect(preview.first?.content == "updated")

        let recoverRows = [ItemRowModel(itemId: map.id, entryId: removeId, typeId: .map)]
        let blockedRows = sut.merge(itemId: map.id, entries: [incoming[0]], recoverEntries: recoverRows)

        #expect(blockedRows.isEmpty)
        #expect(map.entries.map(\.id) == [keepId, removeId])
        #expect(map.entries.first?.content == "updated")

        sut.replace(
            itemId: map.id,
            with: [
                MapEntryModel(id: keepId, name: "Ignored", content: "replaced", coordinates: []),
                MapEntryModel(id: removeId, name: "Ignored", content: "saved", coordinates: [])
            ]
        )

        #expect(map.entries.first?.id == keepId)
        #expect(map.entries.first?.content == "replaced")
        #expect(map.entries.last?.content == "saved")
    }

    /// Map content (entries/pins/rooms) must always stay in game memory while a
    /// game is running — even when the standalone item editor asks to force-save
    /// — matching MapRPG's live-game invariant that map changes never persist
    /// until the game ends.
    @Test func mapMergeStaysMemoryOnlyDuringGameEvenWithForceSave() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let keepId = UUID()
        let map = MapModel(
            id: UUID(),
            name: "Battle Map",
            entries: [MapEntryModel(id: keepId, name: "Keep", content: "old", coordinates: [])]
        )
        root.itemController.replace(model: map, isInsert: true)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        let incoming = [MapEntryModel(id: keepId, name: "Keep", content: "updated mid-game", coordinates: [])]
        _ = sut.merge(itemId: map.id, entries: incoming, recoverEntries: nil, forceSave: true)

        #expect(root.itemController.itemSync(for: map.id, noGame: true)?.entries.first?.content == "old")
        #expect(root.itemController.itemSync(for: map.id)?.entries.first?.content == "updated mid-game")
    }

    /// A map item's own metadata (name/description/tags) is edited through the
    /// shared, generic `EditControllable` surface — not MapRPG's own merge/pin
    /// mutations — so it persists like any other module when the standalone
    /// item editor requests it, even while a game is running.
    @Test func mapMetadataPersistsDuringGameWhenForceSaved() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .item)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        sut.reset(name: "Renamed mid-game", itemId: itemId, forceSave: true)

        #expect(root.itemController.itemSync(for: itemId, noGame: true)?.name == "Renamed mid-game")
    }

    /// Regression test: once an item is already loaded into game memory (e.g.
    /// shown to players), a force-saved standalone-editor edit must update BOTH
    /// the permanent store and the game-memory snapshot — otherwise the default
    /// read path (used by views, including the live game view) keeps showing
    /// the stale game-memory copy even though the edit was "successfully"
    /// persisted underneath.
    @Test func mapMetadataSyncsGameMemoryWhenItemAlreadyLoadedInGame() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .item)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        root.itemController.replaceInGameMemory(model: root.itemController.itemOrEmpty(for: itemId).copy())

        sut.reset(name: "Renamed mid-game", itemId: itemId, forceSave: true)

        #expect(root.itemController.itemSync(for: itemId, noGame: true)?.name == "Renamed mid-game")
        #expect(root.itemController.itemSync(for: itemId)?.name == "Renamed mid-game")
    }

    @Test func addLinkAppendsSimpleModuleMarkdownToDestinationEntry() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let sourceItemId = UUID()
        let destinationEntryId = UUID()
        let destination = MapModel(
            id: UUID(),
            name: "Linked Map",
            entries: [
                MapEntryModel(id: destinationEntryId, name: "Room", content: "Start", coordinates: [])
            ]
        )
        root.itemController.replace(model: destination, isInsert: true)

        sut.add(
            link: "Theme",
            module: .audio,
            itemId: sourceItemId,
            entryId: nil,
            destinationItemId: destination.id,
            destinationEntryId: destinationEntryId
        )

        let content = destination[destinationEntryId].content
        #expect(content.localizedStandardContains("[Theme]"))
        #expect(content.localizedStandardContains("RPG://AUDIOS/0/\(sourceItemId.uuidString)"))
    }
}
#endif
