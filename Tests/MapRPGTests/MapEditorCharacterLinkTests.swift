// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
@Suite("Map editor character links", .serialized)
struct MapEditorCharacterLinkTests {
    @Test("A character is linked once per room, other rooms and older links stay")
    func characterLinkedOncePerRoom() throws {
        // Given
        let room1 = MapEntryModel(id: UUID(), name: "Room 1", content: "Old text", coordinates: rectangle(origin: .zero))
        let room2 = MapEntryModel(id: UUID(), name: "Room 2", content: "", coordinates: rectangle(origin: CGPoint(x: 200, y: 0)))
        let map = makeMap(entries: [room1, room2])
        let context = makeContext(map: map)
        let spiderId = UUID()
        let wolfId = UUID()
        let spider = [ItemRowModel(itemId: spiderId, typeId: .value)]

        // When
        context.controller.addMonsters(entryId: room1.id, location: nil, monsters: spider, number: 1, editorModel: context.session)
        context.controller.addMonsters(entryId: room1.id, location: nil, monsters: spider, number: 1, editorModel: context.session)
        context.controller.addMonsters(entryId: room1.id, location: nil, monsters: [ItemRowModel(itemId: wolfId, typeId: .value)], number: 1, editorModel: context.session)
        context.controller.addMonsters(entryId: room2.id, location: nil, monsters: spider, number: 1, editorModel: context.session)

        // Then
        let copy = try #require(context.session.workingCopy)
        let room1Links = LinkReplaceController.links(for: copy[room1.id].content)
        #expect(copy[room1.id].content.hasPrefix("Old text "))
        #expect(room1Links.map(\.itemId) == [spiderId, wolfId])
        #expect(LinkReplaceController.links(for: copy[room2.id].content).map(\.itemId) == [spiderId])
        #expect(copy.mapPins.count == 4)
        // The stored map is written when the editor commits, not by a mutation.
        let stored = try #require(context.root.itemController.itemSync(for: map.id))
        #expect(stored[room1.id].content == "Old text")
        #expect(stored[room2.id].content.isEmpty)
    }

    @Test("Without a selected room a selected character goes into the first room")
    func characterWithoutRoomGoesIntoFirstRoom() throws {
        // Given
        let room1 = MapEntryModel(id: UUID(), name: "Room 1", content: "", coordinates: rectangle(origin: .zero))
        let room2 = MapEntryModel(id: UUID(), name: "Room 2", content: "", coordinates: rectangle(origin: CGPoint(x: 200, y: 0)))
        let context = makeContext(map: makeMap(entries: [room1, room2]))
        let characterId = UUID()

        // When
        context.controller.addMonsters(
            entryId: nil,
            location: nil,
            monsters: [ItemRowModel(itemId: characterId, typeId: .value)],
            number: 1,
            editorModel: context.session
        )

        // Then
        let copy = try #require(context.session.workingCopy)
        #expect(LinkReplaceController.links(for: copy[room1.id].content).map(\.itemId) == [characterId])
        #expect(copy[room2.id].content.isEmpty)
        let pin = try #require(copy.mapPins.first)
        #expect(pin.location != .zero)
        #expect(copy[room1.id].rect.contains(pin.location))
    }

    @Test("A character set on an existing pin is linked in the pin's room once")
    func characterOnExistingPinIsLinkedOnce() throws {
        // Given
        let room = MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: rectangle(origin: .zero))
        let context = makeContext(map: makeMap(entries: [room]))
        let characterId = UUID()

        // When
        context.controller.appendCharacterLinks([characterId], to: room.id, editorModel: context.session)
        context.controller.appendCharacterLinks([characterId], to: room.id, editorModel: context.session)

        // Then
        let copy = try #require(context.session.workingCopy)
        #expect(LinkReplaceController.links(for: copy[room.id].content).count == 1)
    }
}

private extension MapEditorCharacterLinkTests {
    struct Context {
        let root: MapRootModel
        let controller: MapEditController
        let session: MapEditorSession
    }

    @Test("On a hex map the room under a point is the room, not the hex cell above it (CODE_AUDIT_26 §5.22)")
    func entryLookupSkipsHexCells() throws {
        // Given: a room and a hex cell that covers the whole map and is appended last.
        let room = MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: rectangle(origin: .zero))
        let cell = MapEntryModel(
            id: UUID(), name: "Cell", content: "",
            coordinates: [CGPoint(x: -10, y: -10), CGPoint(x: 390, y: -10), CGPoint(x: 390, y: 390), CGPoint(x: -10, y: 390)],
            isHexGrid: true
        )
        let map = makeMap(entries: [room, cell])
        let context = makeContext(map: map)

        // Then
        #expect(context.session.entry(for: CGPoint(x: 50, y: 50), in: map)?.id == room.id)
        #expect(context.session.entry(for: CGPoint(x: 300, y: 300), in: map) == nil, "outside every room only a cell is there")
    }

    func makeContext(map: MapModel) -> Context {
        let root = MapRootModel.previewFixture(models: [map])
        root.editController.setCurrentItem(model: map)
        let controller = MapEditController(editController: root.editController)
        let session = MapEditorSession(
            map: map,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 400, height: 400),
            configuration: MapEditorConfiguration(mode: .edit, displayMode: .master, isTileEditor: false)
        )
        controller.prepareWorkingCopy(from: map, editorModel: session)
        session.resetEntries(newEntries: map.entries, map: map, appliesFocus: false)
        controller.changeMap(map: map, currentEntryId: nil, editorModel: session)
        return Context(root: root, controller: controller, session: session)
    }

    func makeMap(entries: [MapEntryModel]) -> MapModel {
        MapModel(
            id: UUID(),
            name: "Character Link Map",
            entries: entries,
            displayConfig: DisplayConfigModel(id: UUID(), tileCoordinates: [], border: DisplayBorderViewModel(id: UUID())),
            width: 400,
            height: 400,
            mapPins: []
        )
    }

    func rectangle(origin: CGPoint) -> [CGPoint] {
        [
            origin,
            CGPoint(x: origin.x + 100, y: origin.y),
            CGPoint(x: origin.x + 100, y: origin.y + 100),
            CGPoint(x: origin.x, y: origin.y + 100)
        ]
    }
}
#endif
