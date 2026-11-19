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

    /// A map with two rooms that have outlines, as the quick editor merges them.
    private func mapWithRooms() async throws -> (root: MapRootModel, itemId: UUID, rooms: [MapEntryModel]) {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .map))
        let rooms = [
            MapEntryModel(id: UUID(), name: "Goblin Den", content: "Smells of smoke.", coordinates: [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 1), CGPoint(x: 5, y: 4)]),
            MapEntryModel(id: UUID(), name: "Wolf Pit", content: "A wolf sleeps here.", coordinates: [CGPoint(x: 6, y: 6), CGPoint(x: 9, y: 6), CGPoint(x: 9, y: 9)])
        ]
        rooms.forEach { root.editController.add(entry: $0, into: itemId) }
        return (root, itemId, rooms)
    }

    private var monsterLinks: [LinkEntryModel] {
        QuickLinkScanner.candidates(tableId: UUID(), module: .table, entries: [(UUID(), "Goblin"), (UUID(), "Wolf")])
    }

    /// CODE_AUDIT_Since_3.0.1 §5.1: Quick Link, then Apply in the quick editor, re-created every
    /// room whose title held a table entry name, without its outline.
    @Test func quickLinkThenApplyKeepsRooms() async throws {
        let (root, itemId, rooms) = try await mapWithRooms()
        let sut = root.editController
        let parser = EntryTextParser()
        let text = parser.format(rooms.map { (name: $0.name, content: $0.content) })

        let linked = QuickLinkScanner.applyToContent(monsterLinks, to: text)
        #expect(linked.count == 1, "only the wolf in the content")
        let edited = parser.parse(linked.text).map { sut.create(name: $0.name, content: $0.content) }
        let removed = sut.merge(itemId: itemId, entries: edited, recoverEntries: nil, forceSave: true)

        #expect(removed.isEmpty)
        let saved = root.itemController.itemOrEmpty(for: itemId).entries
        #expect(saved.map(\.id) == rooms.map(\.id))
        #expect(saved.map(\.name) == ["Goblin Den", "Wolf Pit"])
        #expect(saved.map(\.coordinates) == rooms.map(\.coordinates))
        #expect(saved[1].content.contains("](RPG://"))
    }

    /// CODE_AUDIT_Since_3.0.1 §5.1: a title that did gain a link (typed by hand, or by an older
    /// Quick Link) still matches its room, which takes the linked name.
    @Test func linkedTitleKeepsRoom() async throws {
        let (root, itemId, rooms) = try await mapWithRooms()
        let sut = root.editController
        let text = EntryTextParser().format(rooms.map { (name: $0.name, content: $0.content) })

        let linked = QuickLinkScanner.apply(monsterLinks, to: text)
        let edited = EntryTextParser().parse(linked.text).map { sut.create(name: $0.name, content: $0.content) }
        #expect(edited.map(\.name) != rooms.map(\.name), "the titles were linked")
        let removed = sut.merge(itemId: itemId, entries: edited, recoverEntries: nil, forceSave: true)

        #expect(removed.isEmpty)
        let saved = root.itemController.itemOrEmpty(for: itemId).entries
        #expect(saved.map(\.id) == rooms.map(\.id))
        #expect(saved.map(\.coordinates) == rooms.map(\.coordinates))
        #expect(saved.map(\.name) == edited.map(\.name))
        #expect(saved.map { $0.name.withoutLink() } == ["Goblin Den", "Wolf Pit"])
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

    @Test func addPhotoPinsAddsPinsWithoutCharacter() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        let sut = root.editController
        let room = MapEntryModel(
            id: UUID(),
            name: "Room",
            content: "",
            coordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 80), CGPoint(x: 0, y: 80)]
        )
        let map = MapModel(id: UUID(), name: "Photo Pins", entries: [room], pinScale: 1)
        let photoIds = [UUID(), UUID()]

        sut.addPhotoPins(map: map, entryId: room.id, location: nil, photoIds: photoIds)
        sut.addPhotoPins(map: map, entryId: nil, location: CGPoint(x: 7, y: 9), photoIds: [UUID()])

        #expect(map.mapPins.count == 3)
        #expect(map.mapPins.prefix(2).map(\.photoId) == photoIds)
        #expect(map.mapPins.allSatisfy { $0.characterId == nil })
        #expect(map.mapPins.prefix(2).allSatisfy { $0.location != .zero })
        #expect(map.mapPins[2].location == CGPoint(x: 7, y: 9))
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

// MARK: - Hex grid in the entry editors

@MainActor
struct HexGridEditorMergeTests {
    /// A map with real rooms and a hex grid, selected for editing.
    private func hexMap() async throws -> (root: MapRootModel, item: MapModel) {
        let root = try await MockRoot.importTestData()
        let itemId = try #require(root.itemController.itemDataModel.items.first)
        let item = try #require(root.itemController.itemSync(for: itemId))
        root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: itemId, typeId: .map))
        root.editController.createHexMap(model: item, hexMapScale: 0)
        try #require(item.entries.contains { $0.isHexGrid })
        return (root, item)
    }

    @Test func editEntriesHideHexGrid() async throws {
        let (root, item) = try await hexMap()
        #expect(!root.editController.editEntries(for: item).contains { $0.isHexGrid })
    }

    @Test func quickEditorMergeKeepsHexGrid() async throws {
        let (root, item) = try await hexMap()
        let hexIds = item.entries.filter(\.isHexGrid).map(\.id)
        let rooms = root.editController.editEntries(for: item)
        let edited = rooms.map { MapEntryModel(id: UUID(), name: $0.name, content: $0.content + " changed", coordinates: []) }

        // The editor's live preview, then Apply, which merges the preview's result a second time.
        let preview = root.editController.merge(itemId: item.id, entries: edited)
        item.entries = preview
        _ = root.editController.merge(itemId: item.id, entries: preview, recoverEntries: nil, forceSave: true)

        #expect(item.entries.filter(\.isHexGrid).map(\.id) == hexIds)
        let roomsAfter = root.editController.editEntries(for: item)
        #expect(roomsAfter.count == rooms.count)
        #expect(roomsAfter.allSatisfy { $0.content.hasSuffix(" changed") })
        // Rooms keep their id, so links to them survive.
        #expect(roomsAfter.map(\.id) == rooms.map(\.id))
    }

    /// The quick editor's Apply for a text with one room deleted, as the view runs it: the editor
    /// works on a copy, so the real map still holds the room when the removal check runs.
    private func applyDeletingRoom(root: MapRootModel, item: MapModel, deleted: MapEntryModel) -> [ItemRowModel] {
        let editorCopy = item.copy()
        let edited = root.editController.editEntries(for: item)
            .filter { $0.id != deleted.id }
            .map { MapEntryModel(id: UUID(), name: $0.name, content: $0.content, coordinates: []) }
        let entries = root.editController.merge(itemId: item.id, entries: edited)
        editorCopy.entries = entries
        return root.editController.merge(itemId: item.id, entries: entries, recoverEntries: nil, forceSave: true)
    }

    /// A link out of the map's first room: the test data holds a single map.
    private func registerLink(root: MapRootModel, to destination: ItemRowModel, from sourceMap: MapModel) {
        root.editController.linkRegisterController.register(
            links: [LinkRegisterModel(name: "link", source: ItemRowModel(itemId: sourceMap.id, entryId: root.editController.editEntries(for: sourceMap)[0].id, typeId: .map), destination: destination)]
        )
    }

    @Test func deletingRoomIgnoresLinksToTheWholeMap() async throws {
        let (root, item) = try await hexMap()
        registerLink(root: root, to: ItemRowModel(itemId: item.id, typeId: .map), from: item)
        let deleted = root.editController.editEntries(for: item)[1]

        let removeItems = applyDeletingRoom(root: root, item: item, deleted: deleted)

        #expect(removeItems.isEmpty)
        #expect(!item.entries.contains { $0.id == deleted.id })
        #expect(item.entries.contains { $0.isHexGrid })
    }

    @Test func deletingRoomIgnoresLinksToOtherRooms() async throws {
        let (root, item) = try await hexMap()
        let rooms = root.editController.editEntries(for: item)
        registerLink(root: root, to: ItemRowModel(itemId: item.id, entryId: rooms[2].id, typeId: .map), from: item)

        let removeItems = applyDeletingRoom(root: root, item: item, deleted: rooms[1])

        #expect(removeItems.isEmpty)
        #expect(!item.entries.contains { $0.id == rooms[1].id })
    }

    @Test func deletingLinkedRoomAsksBeforeRemoving() async throws {
        let (root, item) = try await hexMap()
        let deleted = root.editController.editEntries(for: item)[1]
        registerLink(root: root, to: ItemRowModel(itemId: item.id, entryId: deleted.id, typeId: .map), from: item)

        let removeItems = applyDeletingRoom(root: root, item: item, deleted: deleted)

        #expect(removeItems.map(\.entryId) == [deleted.id])
        // Nothing is saved before the user decides.
        #expect(item.entries.contains { $0.id == deleted.id })
    }

    @Test func emptyingTheRoomsKeepsHexGrid() async throws {
        let (root, item) = try await hexMap()
        let hexIds = item.entries.filter(\.isHexGrid).map(\.id)

        _ = root.editController.merge(itemId: item.id, entries: [], recoverEntries: [], forceSave: true)

        #expect(item.entries.map(\.id) == hexIds)
    }

    @Test func roomNamedLikeHexCellDoesNotTakeTheCell() async throws {
        let (root, item) = try await hexMap()
        let cell = try #require(item.entries.first { $0.isHexGrid })
        let room = MapEntryModel(id: UUID(), name: cell.name, content: "Room", coordinates: [])

        let merged = root.editController.merge(itemId: item.id, entries: [room])

        #expect(merged.filter { !$0.isHexGrid }.map(\.id) == [room.id])
        #expect(merged.filter(\.isHexGrid).count == item.entries.filter(\.isHexGrid).count)
    }
}
#endif
