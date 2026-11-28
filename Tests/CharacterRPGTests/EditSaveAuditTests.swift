// @copyright André Trettin

#if canImport(Testing)
@testable import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import PhotoRPG
import TableRPG
import Testing

@testable import CharacterRPG

/// Regression tests for CODE_AUDIT_Edit_Save: undo across game start/end and its scope, one undo
/// step per user action, the folder a group leaves during a game, and the sync merge with a
/// queued local edit.
@Suite("Edit and save pipeline (CODE_AUDIT_Edit_Save)")
@MainActor
struct EditSaveAuditTests {
    private static let libraryDescription = "Library description"

    @MainActor
    private struct Fixture {
        let store: GameEditorStore
        let root: CharacterRootModel
        let itemId: UUID

        var game: GameEditorHarness<ItemController> { GameEditorHarness(itemController: root.itemController) }
        var editController: EditController { root.editController }

        func library(_ id: UUID? = nil) -> ValueModel? {
            root.itemController.itemSync(for: id ?? itemId, noGame: true)
        }
    }

    private func makeFixture() async throws -> Fixture {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let root = CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: PhotoRootModel.testRoot(), tableRoot: TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot))
        let store = try GameEditorStore(bundles: [CoreRPG.Resources.bundle, CharacterRPG.Resources.bundle])
        root.itemController.itemDataModel.dataController = DataController(context: store.context, token: NetworkModules.value.token)
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.update(id: itemId, name: "Aria", description: Self.libraryDescription, category: nil, tags: ["hero"], forceSave: false)
        root.editController.editorModel.undoManaged.removeAll()
        return Fixture(store: store, root: root, itemId: itemId)
    }

    private func addItem(_ fixture: Fixture, name: String, type: ItemListCategory = .item) async -> UUID {
        let id = await fixture.root.itemController.addNew(type: type)
        fixture.editController.reset(name: name, itemId: id, forceSave: false)
        return id
    }

    // MARK: - §5.1 undo and the game generation

    @Test("A game-memory edit cannot be undone after the game ended, and the library stays")
    func undoHistoryEndsWithTheGame() async throws {
        let fixture = try await makeFixture()
        fixture.game.startGame()
        fixture.game.loadIntoGame(fixture.itemId)
        fixture.editController.reset(name: "Session Name", itemId: fixture.itemId, forceSave: false)
        #expect(fixture.editController.canUndo)

        fixture.game.endGame()

        #expect(!fixture.editController.canUndo, "the step describes a game copy that no longer exists")
        fixture.editController.undo()
        #expect(fixture.library()?.name == "Aria")
    }

    @Test("A library edit made before the game cannot be undone into game memory")
    func undoHistoryEndsWithTheGameStart() async throws {
        let fixture = try await makeFixture()
        fixture.editController.reset(name: "Before", itemId: fixture.itemId, forceSave: false)
        #expect(fixture.editController.canUndo)

        fixture.game.startGame()

        #expect(!fixture.editController.canUndo)
    }

    // MARK: - §5.2 undo reverts only its own change

    @Test("Undo of a forced edit reverts only that field, not a later synced change")
    func forcedUndoKeepsLaterSyncedChange() async throws {
        let fixture = try await makeFixture()
        fixture.game.startGame()
        fixture.game.loadIntoGame(fixture.itemId)
        fixture.editController.reset(name: "Lyra", itemId: fixture.itemId, forceSave: true)
        #expect(fixture.library()?.name == "Lyra")

        // Another device changes the description; the sync merge applies it to the library.
        let synced = try #require(fixture.library()?.copy())
        synced.description = "Synced description"
        fixture.root.itemController.applyMergedUpdate(model: synced)

        fixture.editController.undo()

        #expect(fixture.library()?.name == "Aria")
        #expect(fixture.library()?.description == "Synced description", "a whole-item snapshot reverted the sync")
        #expect(fixture.game.game(fixture.itemId)?.name == "Aria", "the game copy is reverted too")
    }

    // MARK: - §5.5 one step per user action

    @Test("Moving an entry to another item is one undo step that puts it back")
    func entryMoveIsOneUndoStep() async throws {
        let fixture = try await makeFixture()
        let entry = ValueEntryModel(id: UUID(), name: "Notes", type: .text, value: "Brave")
        fixture.editController.add(entry: entry, itemId: fixture.itemId, forceSave: false)
        let targetId = await addItem(fixture, name: "Target")
        fixture.editController.editorModel.undoManaged.removeAll()

        let moved = fixture.editController.move(itemId: fixture.itemId, entryId: entry.id, into: ItemRowModel(itemId: targetId, typeId: .value), forceSave: false)
        try #require(moved)
        #expect(fixture.editController.editorModel.undoManaged.undoDepth == 1)

        fixture.editController.undo()

        #expect(fixture.library()?.entries.contains { $0.id == entry.id } == true)
        #expect(fixture.library(targetId)?.entries.contains { $0.id == entry.id } == false)
    }

    // MARK: - §5.8 the folder a group leaves during a game

    @Test("Move into group during a game, forced: the library item leaves its folder")
    func moveIntoGroupForcedLeavesFolderInLibrary() async throws {
        let fixture = try await makeFixture()
        let folderId = await addItem(fixture, name: "Folder", type: .folder)
        let memberId = await addItem(fixture, name: "Member")
        fixture.editController.addItem(itemId: memberId, parentId: folderId)
        try #require(fixture.library(memberId)?.parentId == folderId)
        fixture.game.startGame()

        let entryId = fixture.editController.moveIntoGroup(itemId: memberId, into: fixture.itemId, forceSave: true)

        #expect(entryId != nil)
        #expect(fixture.library(memberId)?.parentId == nil)
        #expect(fixture.library(memberId)?.groupId == fixture.itemId)
        #expect(fixture.library(folderId)?.entries.contains { $0.childId == memberId } == false, "the folder kept listing the hidden group")
    }

    @Test("Move into group during a game, unforced: the library keeps the folder")
    func moveIntoGroupUnforcedKeepsLibraryFolder() async throws {
        let fixture = try await makeFixture()
        let folderId = await addItem(fixture, name: "Folder", type: .folder)
        let memberId = await addItem(fixture, name: "Member")
        fixture.editController.addItem(itemId: memberId, parentId: folderId)
        fixture.game.startGame()

        _ = fixture.editController.moveIntoGroup(itemId: memberId, into: fixture.itemId, forceSave: false)

        #expect(fixture.library(memberId)?.parentId == folderId)
        #expect(fixture.library(memberId)?.groupId == nil)
    }

    // MARK: - §3.1 sync merge with a queued local edit

    @Test("A synced row merges with a queued local edit instead of replacing it")
    func syncMergeKeepsQueuedLocalEdit() async throws {
        let fixture = try await makeFixture()
        try await fixture.root.itemController.dataControllable?.flushPendingOperations()
        try await fixture.root.itemController.dataControllable?.save()
        let remote = try #require(fixture.library()?.copy())

        fixture.editController.reset(name: "Local Name", itemId: fixture.itemId, forceSave: false)
        remote.description = "Remote description"
        let hasLocalEdit = await fixture.root.itemController.dataControllable?.hasPendingOperation(for: fixture.itemId) ?? false
        #expect(hasLocalEdit)

        await fixture.root.itemController.mergeUpdates(model: remote, keepingLocalEdit: hasLocalEdit)

        #expect(fixture.library()?.name == "Local Name", "the queued rename disappeared from the UI")
        #expect(fixture.library()?.description == "Remote description")
    }
}
#endif
