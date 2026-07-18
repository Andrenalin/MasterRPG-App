// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import SwiftUI
import Testing

@testable import MapRPG

@Suite("Map editor interaction models")
@MainActor
struct MapEditorInteractionModelTests {
    @Test("External map surfaces do not own the shared game toolbar session")
    func toolbarSessionRegistrationIsConfigurable() {
        let main = MapEditorConfiguration(mode: .player, displayMode: .player)
        let external = MapEditorConfiguration(
            mode: .player,
            displayMode: .player,
            registersGameToolbarSession: false
        )

        #expect(main.registersGameToolbarSession)
        #expect(!external.registersGameToolbarSession)
    }

    @Test("Needles render from top-left to bottom-right without changing persisted indices")
    func needlePainterOrder() {
        let entryId = UUID()
        let coordinates = [
            CGPoint(x: 300, y: 300),
            CGPoint(x: 80, y: 40),
            CGPoint(x: 20, y: 40),
            CGPoint(x: 10, y: 200),
        ]
        let model = makeEntryModel(entryId: entryId, coordinates: coordinates)

        let rendered = model.renderedNeedlePoints(for: entryId)

        #expect(rendered.map(\.coordinate) == [
            CGPoint(x: 20, y: 40),
            CGPoint(x: 80, y: 40),
            CGPoint(x: 10, y: 200),
            CGPoint(x: 300, y: 300),
        ])
        #expect(rendered.map(\.coordinateIndex) == [2, 1, 3, 0])
    }

    @Test("Needle movement preserves stable identity and commits one coordinate")
    func needleMovePreservesIdentity() throws {
        let entryId = UUID()
        let model = makeEntryModel(
            entryId: entryId,
            coordinates: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)]
        )
        let point = try #require(
            model.renderedNeedlePoints(for: entryId).first { $0.coordinateIndex == 0 }
        )
        let stableId = point.id

        model.moveNeedle(point, to: CGPoint(x: 50, y: 60), entryId: entryId)

        #expect(point.id == stableId)
        #expect(model.entry(entryId).coordinates == [
            CGPoint(x: 50, y: 60),
            CGPoint(x: 30, y: 40),
        ])
    }

    @Test("Pin reconciliation preserves sibling node identity")
    func pinReconciliationPreservesNodes() throws {
        let first = MapPinModel(id: UUID(), name: "First", location: CGPoint(x: 10, y: 20))
        let second = MapPinModel(id: UUID(), name: "Second", location: CGPoint(x: 30, y: 40))
        let model = MapPinViewModel(mapPins: [first, second], pointer: .empty)
        let firstNode = try #require(model.pinNode(for: first.id))
        let secondNode = try #require(model.pinNode(for: second.id))
        var updatedFirst = first
        updatedFirst.location = CGPoint(x: 70, y: 80)

        model.mapPins = [updatedFirst, second]

        #expect(model.pinNode(for: first.id) === firstNode)
        #expect(model.pinNode(for: second.id) === secondNode)
        #expect(firstNode.pin.location == CGPoint(x: 70, y: 80))
    }

    @Test("Dragging one pin in a 200-pin map commits once and leaves sibling nodes untouched")
    func heavyPinDragIsIsolated() throws {
        let pins = (0..<200).map { index in
            MapPinModel(
                id: UUID(),
                name: "Pin \(index)",
                location: CGPoint(x: CGFloat(index), y: CGFloat(index * 2))
            )
        }
        let model = MapPinViewModel(mapPins: pins, pointer: .empty)
        let target = try #require(model.pinNode(for: pins[0].id))
        let siblingNodes = model.mapPinNodes.dropFirst().map { $0 }
        let siblingPins = siblingNodes.map(\.pin)
        let originalLayerNodeIds = model.ordinaryPinNodes.map(\.id)
        var committedMoves = 0
        model.configureInteractionHandler { event in
            if case .move = event {
                committedMoves += 1
            }
        }

        target.beginMove()
        target.move(by: CGSize(width: 20, height: 30))

        #expect(committedMoves == 1)
        #expect(target.pin.location == CGPoint(x: 20, y: 30))
        #expect(model.ordinaryPinNodes.map(\.id) == originalLayerNodeIds)
        for (index, sibling) in siblingNodes.enumerated() {
            #expect(model.mapPinNodes[index + 1] === sibling)
            #expect(sibling.pin == siblingPins[index])
        }
    }

    @Test("Editor pin actions mutate the store before emitting one event")
    func editorPinActionIsModelDriven() throws {
        let pin = MapPinModel(id: UUID(), name: "Token")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)
        let node = try #require(model.pinNode(for: pin.id))
        var events: [MapPinInteractionEvent] = []
        model.configureInteractionHandler { event in
            events.append(event)
        }

        node.perform(.resize, context: .editor)

        #expect(node.pin.size == .large)
        #expect(events.count == 1)
        guard case let .action(.resize, emittedPin, false, .editor) = events[0] else {
            Issue.record("Expected one editor resize event")
            return
        }
        #expect(emittedPin.size == .large)
    }

    @Test("Successive pin taps open and close the action menu")
    func pinTapTogglesActionMenu() throws {
        let pin = MapPinModel(id: UUID(), name: "Token")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)
        let node = try #require(model.pinNode(for: pin.id))

        node.handleTap(context: .editor)

        #expect(node.isExpanded)
        #expect(model.isExpandedId == pin.id)

        node.handleTap(context: .editor)

        #expect(!node.isExpanded)
        #expect(model.isExpandedId == nil)
    }

    @Test("Switching maps discards stale editor interaction state")
    func switchingMapsReseedsEditorState() {
        let firstEntry = MapEntryModel(
            id: UUID(),
            name: "First room",
            content: "",
            coordinates: [CGPoint(x: 10, y: 10)]
        )
        let firstPin = MapPinModel(id: UUID(), name: "First pin")
        let firstMap = MapModel(
            id: UUID(),
            name: "First map",
            entries: [firstEntry],
            mapPins: [firstPin]
        )
        firstMap.pointer = MapPinModel(id: UUID(), name: "First pointer", isShown: true)

        let model = MapEditorSession(
            map: firstMap,
            image: AKImage(),
            photoDegrees: 0,
            containerSize: CGSize(width: 800, height: 600),
            configuration: MapEditorConfiguration(
                mode: .edit,
                displayMode: .master
            )
        )
        model.workingCopy = firstMap
        model.entries.resetEntries(mapId: firstMap.id, entries: firstMap.entries)
        model.editEntries.resetEntries(mapId: firstMap.id, entries: [firstEntry])
        model.focusId = firstEntry.id
        model.appeared = true
        model.pins.isExpandedId = firstPin.id
        model.editEntries.needleInteraction.dragCoordinate = CGPoint(x: 30, y: 40)

        let secondPin = MapPinModel(id: UUID(), name: "Second pin")
        let secondMap = MapModel(
            id: UUID(),
            name: "Second map",
            mapPins: [secondPin]
        )
        secondMap.pointer = MapPinModel(id: UUID(), name: "Second pointer", isShown: true)

        model.changeImage(map: secondMap)

        #expect(model.mapId == secondMap.id)
        #expect(model.workingCopy == nil)
        #expect(model.focusId == nil)
        #expect(model.pins.mapPins == [secondPin])
        #expect(model.pins.pointer == secondMap.pointer)
        #expect(model.pins.isExpandedId == nil)
        #expect(model.entries.mapId == secondMap.id)
        #expect(model.entries.entries.isEmpty)
        #expect(model.editEntries.mapId == secondMap.id)
        #expect(model.editEntries.entries.isEmpty)
        #expect(model.editEntries.needleInteraction.dragCoordinate == nil)
    }

    private func makeEntryModel(
        entryId: UUID,
        coordinates: [CGPoint]
    ) -> MapEntryViewerModel {
        MapEntryViewerModel(
            mapId: UUID(),
            entries: [MapEntryModel(
                id: entryId,
                name: "Room",
                content: "",
                coordinates: coordinates
            )]
        )
    }
}
#endif
