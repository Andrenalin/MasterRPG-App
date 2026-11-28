// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// The editor window (macOS, iPad, visionOS) stays open while a game runs. Every edit it makes
/// reaches the database, and the game's in-memory copy of a loaded dice set shows it too, while a
/// change only the game copy has (here its description) stays out of the library.
@Suite("Dice editor window during a game")
@MainActor
struct DiceEditorWindowDuringGameTests {
    private static let libraryDescription = "Library description"
    private static let sessionDescription = "Session description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: DiceRootModel
        let itemId: UUID
        let firstDie: DieModel

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }
        var editController: EditController { root.editController }

        func expectEdit(sourceLocation: SourceLocation = #_sourceLocation, _ isEdited: (DiceModel) -> Bool) async throws {
            try await game.expectEdit(
                itemId,
                libraryDescription: DiceEditorWindowDuringGameTests.libraryDescription,
                sessionDescription: DiceEditorWindowDuringGameTests.sessionDescription,
                sourceLocation: sourceLocation,
                isEdited
            )
        }
    }

    /// A dice set with one d20 in the library and the database, a running game and, when
    /// `loaded`, the set in game memory with a change of its own.
    private func makeFixture(loaded: Bool = true) async throws -> Fixture {
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, DiceRPG.Resources.bundle])
        let root = DiceRootModel.testRoot()
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.dice.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Attack", description: Self.libraryDescription, category: nil, tags: ["combat"], forceSave: false)
        root.editController.add(die: DieModel(id: UUID(), die: .twenty), itemId: itemId, forceSave: false)
        let firstDie = try #require(root.itemController.itemSync(for: itemId)?.dice.first)

        let fixture = Fixture(store: store, root: root, itemId: itemId, firstDie: firstDie)
        fixture.game.startGame()
        if loaded {
            fixture.game.loadIntoGame(itemId) { $0.description = Self.sessionDescription }
        }
        // Selecting the item in the editor starts its undo history.
        root.editController.editorModel.undoManaged.removeAll()
        return fixture
    }

    @Test("The header editor's name and tags reach the database and the game copy")
    func headerEdit() async throws {
        let fixture = try await makeFixture()

        fixture.editController.update(id: fixture.itemId, name: "Power Attack", description: nil, category: nil, tags: ["combat", "melee"], forceSave: true)

        try await fixture.expectEdit { $0.name == "Power Attack" && $0.tags == ["combat", "melee"] }
    }

    @Test("Dice added from the dice bag and removed in the viewer reach the database and the game copy")
    func addAndRemoveDie() async throws {
        let fixture = try await makeFixture()

        #expect(fixture.editController.add(die: DieModel(id: UUID(), die: .six), itemId: fixture.itemId, forceSave: true))
        try await fixture.expectEdit { $0.dice.map(\.die) == [.twenty, .six] }

        fixture.editController.remove(die: fixture.firstDie, itemId: fixture.itemId, forceSave: true)
        try await fixture.expectEdit { $0.dice.map(\.die) == [.six] }
    }

    @Test("Coup and fumble options added and removed in the editor reach the database and the game copy")
    func coupAndFumble() async throws {
        let fixture = try await makeFixture()

        fixture.editController.add(coup: 20, isDiceValueCoup: true, itemId: fixture.itemId, forceSave: true)
        fixture.editController.add(fumble: 1, isDiceValueFumble: true, itemId: fixture.itemId, forceSave: true)
        try await fixture.expectEdit { $0.coupValues == [.diceValue(20)] && $0.fumbleValues == [.diceValue(1)] }

        fixture.editController.remove(coup: .diceValue(20), itemId: fixture.itemId, forceSave: true)
        fixture.editController.remove(fumble: .diceValue(1), itemId: fixture.itemId, forceSave: true)
        try await fixture.expectEdit { $0.coupValues.isEmpty && $0.fumbleValues.isEmpty }
    }

    @Test("Reroll options added and removed in the editor reach the database and the game copy")
    func reroll() async throws {
        let fixture = try await makeFixture()

        fixture.editController.add(reroll: 1, value: 1, isMaxDiceValue: false, itemId: fixture.itemId, forceSave: true)
        let option = DiceModel.RerollOption(number: 1, value: 1, maxDiceValue: false)
        try await fixture.expectEdit { $0.rerollOptions == [option] }

        fixture.editController.remove(reroll: option, itemId: fixture.itemId, forceSave: true)
        try await fixture.expectEdit { $0.rerollOptions.isEmpty }
    }

    @Test("Modifier, compare option and compare value set in the editor reach the database and the game copy")
    func modifierAndCompare() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(modifier: 3, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(compareOption: .equalHigher, itemId: fixture.itemId, forceSave: true)
        fixture.editController.reset(compareValue: 15, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.modifier == 3 && $0.compareOption == .equalHigher && $0.compareValue == 15 }
    }

    @Test("The add-dice-every value set in the editor reaches the database and the game copy")
    func addDiceEvery() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(addValue: 5, itemId: fixture.itemId, forceSave: true)

        try await fixture.expectEdit { $0.addDiceEvery == 5 }
    }

    @Test("A toggle in the editor (sum up, percent, reorder) reaches the database and the game copy")
    func toggles() async throws {
        let fixture = try await makeFixture()
        // What `ToggleDiceValue` saves.
        let item = try #require(fixture.editController.editModel(for: fixture.itemId))
        item.sumUp.toggle()
        item.reorderDice.toggle()
        let sumUp = item.sumUp
        fixture.editController.save(updated: item, message: "value toggle", forceSave: true)

        try await fixture.expectEdit { $0.sumUp == sumUp && $0.reorderDice }
    }

    @Test("Undo and redo of an editor edit change the database and the game copy")
    func undoAndRedo() async throws {
        let fixture = try await makeFixture()
        fixture.editController.reset(modifier: 4, itemId: fixture.itemId, forceSave: true)

        fixture.editController.undo()
        try await fixture.expectEdit { $0.modifier == 0 }

        fixture.editController.redo()
        try await fixture.expectEdit { $0.modifier == 4 }
    }

    @Test("An edit of a dice set the game has not loaded reaches the database and makes no game copy")
    func editOfDiceNotInGame() async throws {
        let fixture = try await makeFixture(loaded: false)

        fixture.editController.reset(modifier: 2, itemId: fixture.itemId, forceSave: true)

        try await fixture.game.expectLibraryEditWithoutGameCopy(fixture.itemId) { $0.modifier == 2 }
    }

    @Test("Without the editor, an in-game edit stays in game memory")
    func inGameEditStaysInGameMemory() async throws {
        let fixture = try await makeFixture()

        fixture.editController.reset(modifier: 2, itemId: fixture.itemId, forceSave: false)

        try await fixture.game.expectGameOnly(fixture.itemId) { $0.modifier == 2 }
    }
}
#endif
