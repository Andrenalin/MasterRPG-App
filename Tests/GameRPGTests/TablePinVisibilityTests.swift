// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import GameRPG
@testable import MapRPG

/// CODE_AUDIT_26 §10.3: who sees which pin on the table, and the map-change state machine.
@MainActor
@Suite("Table pin visibility and map change")
struct TablePinVisibilityTests {
    private static let square = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100)
    ]

    private func map(pins: [MapPinModel], hiddenRoom: Bool = true) -> MapModel {
        let room = MapEntryModel(id: UUID(), name: "Crypt", content: "", coordinates: Self.square, isShown: !hiddenRoom)
        return MapModel(id: UUID(), name: "Visibility", entries: [room], mapPins: pins)
    }

    @Test("The game master sees every pin, hidden ones and monsters in fog included")
    func gameMasterSeesEverything() {
        let hidden = MapPinModel(id: UUID(), name: "Hidden", isShown: false)
        let fogged = MapPinModel(id: UUID(), name: "Ghoul", location: CGPoint(x: 50, y: 50))
        let model = map(pins: [hidden, fogged])

        let visible = TablePinVisibility.visiblePins(allPins: TablePinVisibility.allPins(of: model), mapModel: model, isGameMaster: true)

        #expect(Set(visible.map(\.id)) == [hidden.id, fogged.id])
    }

    @Test("Players do not see hidden pins, nor monsters covered by fog, but see their own kind in fog")
    func playersFollowFogAndShownFlag() {
        let hidden = MapPinModel(id: UUID(), name: "Hidden", location: CGPoint(x: 500, y: 500), isShown: false)
        let foggedMonster = MapPinModel(id: UUID(), name: "Ghoul", location: CGPoint(x: 50, y: 50))
        let foggedPlayer = MapPinModel(id: UUID(), name: "Hero", location: CGPoint(x: 50, y: 50), isPlayer: true)
        let openMonster = MapPinModel(id: UUID(), name: "Rat", location: CGPoint(x: 500, y: 500))
        let model = map(pins: [hidden, foggedMonster, foggedPlayer, openMonster])

        let visible = TablePinVisibility.visiblePins(allPins: TablePinVisibility.allPins(of: model), mapModel: model, isGameMaster: false)

        #expect(Set(visible.map(\.id)) == [foggedPlayer.id, openMonster.id])
    }

    @Test("A revealed room no longer hides its monsters")
    func revealedRoomShowsMonsters() {
        let monster = MapPinModel(id: UUID(), name: "Ghoul", location: CGPoint(x: 50, y: 50))
        let model = map(pins: [monster], hiddenRoom: false)

        let visible = TablePinVisibility.visiblePins(allPins: TablePinVisibility.allPins(of: model), mapModel: model, isGameMaster: false)

        #expect(visible.map(\.id) == [monster.id])
    }

    @Test("The pointer is a pin only while it is shown, and players see it inside fog")
    func pointerFollowsItsShownFlag() {
        let model = map(pins: [])
        model.pointer.location = CGPoint(x: 50, y: 50)

        model.pointer.isShown = false
        #expect(TablePinVisibility.allPins(of: model).isEmpty)

        model.pointer.isShown = true
        let all = TablePinVisibility.allPins(of: model)
        #expect(all.map(\.id) == [model.pointer.id])
        let visible = TablePinVisibility.visiblePins(allPins: all, mapModel: model, isGameMaster: false)
        #expect(visible.map(\.id) == [model.pointer.id])
    }

    @Test("A pin id listed twice is shown once; without a map nothing is shown")
    func duplicatesAndNoMap() {
        let pin = MapPinModel(id: UUID(), name: "Twice", location: CGPoint(x: 500, y: 500))
        let model = map(pins: [pin, pin])

        let visible = TablePinVisibility.visiblePins(allPins: model.mapPins, mapModel: model, isGameMaster: false)

        #expect(visible.count == 1)
        #expect(TablePinVisibility.allPins(of: nil).isEmpty)
    }

    // MARK: - Map change

    private func tableOnTwoMaps(secondPhotoId: UUID? = nil) -> (game: GameTableModel, mapRoot: MapRootModel, first: MapModel, second: MapModel) {
        let first = MapModel(id: MapModel.previewId, name: "First")
        let second = MapModel(id: UUID(), name: "Second", photoId: secondPhotoId)
        let mapRoot = MapRootModel.previewFixture(models: [first, second])
        let game = GameTableModel(mapRoot: mapRoot, photoRoot: mapRoot.photoRoot)
        game.currentMapId = first.id
        return (game, mapRoot, first, second)
    }

    @Test("Showing another map drops the previous map's selection and photo state")
    func mapChangeResetsMapState() async {
        let (game, mapRoot, _, second) = tableOnTwoMaps()
        game.selectedPinId = UUID()
        game.currentPhotoId = UUID()
        game.currentPhotoVersion = 3
        game.currentMapDegrees = 90

        mapRoot.gameController.setGame(item: second.copy(), itemId: second.id)
        await game.handleMapChange(isGameMaster: true)

        #expect(game.currentMapId == second.id)
        #expect(game.selectedPinId == nil)
        #expect(game.currentPhotoId == nil)
        #expect(game.currentPhotoVersion == nil)
        #expect(game.currentMapDegrees == 0)
        #expect(game.currentMapImage == nil)
    }

    @Test("A map whose photo cannot load remembers nothing about it, so the next sync retries")
    func failedPhotoLoadIsNotRemembered() async {
        let (game, mapRoot, _, second) = tableOnTwoMaps(secondPhotoId: UUID())

        mapRoot.gameController.setGame(item: second.copy(), itemId: second.id)
        await game.handleMapChange(isGameMaster: true)

        #expect(game.currentMapId == second.id)
        #expect(game.currentMapImage == nil)
        #expect(game.currentPhotoId == nil, "a failed load is not recorded as the shown photo")
    }

    @Test("Overlapping map changes end on the newest map")
    func newestMapChangeWins() async {
        let (game, mapRoot, first, second) = tableOnTwoMaps()

        mapRoot.gameController.setGame(item: first.copy(), itemId: first.id)
        let older = Task { @MainActor in await game.handleMapChange(isGameMaster: true) }
        mapRoot.gameController.setGame(item: second.copy(), itemId: second.id)
        await game.handleMapChange(isGameMaster: true)
        await older.value

        #expect(game.currentMapId == second.id)
    }

    @Test("No current map clears the table's map state")
    func noCurrentMapClearsState() async {
        let (game, mapRoot, _, _) = tableOnTwoMaps()
        game.selectedPinId = UUID()
        mapRoot.mapGameControllable.gameModel.clearCurrent()

        await game.handleMapChange(isGameMaster: false)

        #expect(game.currentMapId == nil)
        #expect(game.selectedPinId == nil)
        #expect(game.currentMapImage == nil)
    }
}
#endif
