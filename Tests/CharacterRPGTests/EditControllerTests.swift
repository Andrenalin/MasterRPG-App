// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

@MainActor
struct EditControllerTests {

    @MainActor
    private func captureIds(_ root: CharacterRootModel) -> Set<UUID> {
        Set(root.itemController.itemDataModel.items)
    }

    private func requireSingleNewId(before: Set<UUID>, root: CharacterRootModel) async throws -> UUID {
        let added = captureIds(root).subtracting(before)
        return try #require(added.first, "Expected exactly one new item but found \(added.count)")
    }

    @MainActor
    private static func makeRoot() -> CharacterRootModel {
        let diceRoot = DiceRootModel.testRoot()
        let pdfRoot = PdfRootModel.testRoot()
        let photoRoot = PhotoRootModel.testRoot()
        let tableRoot = TableRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot)
        return CharacterRootModel.testRoot(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
    }

    @MainActor
    private func firstId(in ids: Set<UUID>, of root: CharacterRootModel, where predicate: (ValueModel) -> Bool) -> UUID? {
        ids.first { predicate(root.itemController.itemOrEmpty(for: $0)) }
    }

    // MARK: - addNewGroup

    @Test func addNewGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let groupEntry = try #require(item.entries.first(where: { $0.id == entryId }))
        let groupItemId = try #require(groupEntry.valueId)

        let groupItem = root.itemController.itemOrEmpty(for: groupItemId)
        #expect(groupItem.groupId == itemId)
        #expect(groupItem.parentId == nil)
        #expect(groupItem.displayState == 1)
    }

    // MARK: - canBecomeGroup / convertToGroup

    @Test func canBecomeGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        #expect(sut.canBecomeGroup(itemId: itemId))

        let entryId = await sut.addNewGroup(itemId: itemId)
        let item = root.itemController.itemOrEmpty(for: itemId)
        let groupItemId = try #require(item.entries.first(where: { $0.id == entryId })?.valueId)

        #expect(sut.canBecomeGroup(itemId: groupItemId) == false)
    }

    @Test func convertToGroupCreatesNewGroupFromEntry() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entry = ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "A collection of skills.")
        sut.add(entry: entry, itemId: itemId)

        let groupId = await sut.convertToGroup(itemId: itemId, entryId: entry.id, existingItemId: nil)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let updatedEntry = try #require(item.entries.first(where: { $0.id == entry.id }))
        #expect(updatedEntry.valueId == groupId)

        let groupItem = root.itemController.itemOrEmpty(for: groupId)
        #expect(groupItem.groupId == itemId)
        #expect(groupItem.name == "Skills")
        #expect(groupItem.description == "A collection of skills.")
        #expect(groupItem.displayState == 1)
    }

    @Test func convertToGroupReusesExistingItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entry = ValueEntryModel(id: UUID(), name: "Old Name", type: .text, value: "Old content.")
        sut.add(entry: entry, itemId: itemId)

        let existingItemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Inventory", itemId: existingItemId)
        sut.reset(description: "All carried items.", itemId: existingItemId)

        let groupId = await sut.convertToGroup(itemId: itemId, entryId: entry.id, existingItemId: existingItemId)
        #expect(groupId == existingItemId)

        let updatedExisting = root.itemController.itemOrEmpty(for: existingItemId)
        #expect(updatedExisting.groupId == itemId)
        #expect(updatedExisting.displayState == 1)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let updatedEntry = try #require(item.entries.first(where: { $0.id == entry.id }))
        #expect(updatedEntry.valueId == existingItemId)
        #expect(updatedEntry.name == "Inventory")
        #expect(updatedEntry.value == "All carried items.")
    }

    @Test func inlineValueEditingAndMergeHelpers() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let textEntry = ValueEntryModel(id: UUID(), name: "Text", type: .text, value: "old")
        let decimalEntry = ValueEntryModel(id: UUID(), name: "Decimal", type: .decimal, value: "0|1.5")
        let numberEntry = ValueEntryModel(id: UUID(), name: "Number", type: .number, value: "0|2")
        let selectedEntry = ValueEntryModel(id: UUID(), name: "Selected", type: .selection, value: "")
        sut.add(entry: textEntry, itemId: itemId)
        sut.add(entry: decimalEntry, itemId: itemId)
        sut.add(entry: numberEntry, itemId: itemId)
        sut.add(entry: selectedEntry, itemId: itemId)

        #expect(sut.entryValue(itemId: itemId, entryId: textEntry.id) == "old")
        #expect(sut.entryValue(itemId: itemId, entryId: nil).isEmpty)
        #expect(sut.entryValueAsDecimal(itemId: itemId, entryId: decimalEntry.id) == 1.5)
        #expect(sut.entryValueAsDecimal(itemId: itemId, entryId: nil) == 0)
        #expect(sut.entryValueAsNumber(itemId: itemId, entryId: numberEntry.id) == 2)
        #expect(sut.entryValueAsNumber(itemId: itemId, entryId: nil) == 0)
        #expect(!sut.entryValueAsSelected(itemId: itemId, entryId: selectedEntry.id))
        #expect(!sut.entryValueAsSelected(itemId: itemId, entryId: nil))

        sut.updateValue(itemId: itemId, entryId: textEntry.id, value: "new")
        sut.updateValue(itemId: itemId, entryId: decimalEntry.id, decimal: 2.75)
        sut.updateValue(itemId: itemId, entryId: numberEntry.id, number: 7)
        sut.updateValue(itemId: itemId, entryId: selectedEntry.id, selected: true)
        sut.updateValue(itemId: itemId, entryId: nil, value: "ignored")
        sut.updateValue(itemId: itemId, entryId: nil, decimal: 5)
        sut.updateValue(itemId: itemId, entryId: nil, number: 5)
        sut.updateValue(itemId: itemId, entryId: nil, selected: false)

        #expect(sut.entryValue(itemId: itemId, entryId: textEntry.id) == "new")
        #expect(sut.entryValueAsDecimal(itemId: itemId, entryId: decimalEntry.id) == 2.75)
        #expect(sut.entryValueAsNumber(itemId: itemId, entryId: numberEntry.id) == 7)
        #expect(sut.entryValueAsSelected(itemId: itemId, entryId: selectedEntry.id))

        #expect(sut.create(name: "Count", content: "42").type == .number)
        #expect(sut.create(name: "Ratio", content: "3.5").type == .decimal)
        #expect(sut.create(name: "Note", content: "hello").type == .text)
        // Number characters alone do not make a number: a range, a fraction and a list stay text.
        #expect(sut.create(name: "Damage", content: "5-10").type == .text)
        #expect(sut.create(name: "Ratio", content: "3/4").type == .text)
        #expect(sut.create(name: "List", content: "1,2,3").type == .text)

        let merged = sut.merge(itemId: itemId, entries: [
            ValueEntryModel(id: UUID(), name: "Text", type: .text, value: "merged"),
            ValueEntryModel(id: UUID(), name: "Fresh", type: .text, value: "added")
        ])
        #expect(merged.first { $0.name == "Text" }?.id == textEntry.id)
        #expect(merged.first { $0.name == "Text" }?.value == "merged")
        #expect(merged.contains { $0.name == "Fresh" })

        let unresolved = sut.merge(itemId: UUID(), entries: [textEntry])
        #expect(unresolved == [textEntry])

        let recovery = sut.merge(
            itemId: itemId,
            entries: [ValueEntryModel(id: UUID(), name: "Text", type: .text, value: "only")],
            recoverEntries: [ItemRowModel(itemId: itemId, entryId: numberEntry.id, typeId: .value)]
        )
        #expect(recovery.isEmpty)
        #expect(root.itemController.itemOrEmpty(for: itemId).entries.contains { $0.id == numberEntry.id })
    }

    /// Reproduces the reported "character update never arrives at the
    /// gamemaster" scenario end-to-end through the real production write
    /// path (`EditController.updateValue` → `EditControllable.save` →
    /// `ItemControllable.replace`), not just the resolution math in
    /// isolation. A hit-points entry set up the normal way — pure link, no
    /// local "|" yet — used to read back a false "0" baseline (fixed by
    /// `resolvedBaseAndCurrent`).
    ///
    /// Note this test does *not* assert the permanent/persisted item stays
    /// untouched — `saveGameDataToPermanent` deliberately force-persists
    /// every live in-game quick-edit into it too (see that function's own
    /// doc comment); that's pre-existing, intentional behavior, not part of
    /// this bug. What actually matters for "does the update reach the
    /// gamemaster" is what `gameValueEntryUpdate` sends and what the
    /// master's own `applyGameValueEntryUpdate`/`LinkController.calculate`
    /// resolve it back to — checked below.
    @Test func linkedHitPointsEntryStepperResolvesRealCurrentAndStaysInGameMemory() async throws {
        let root = Self.makeRoot()
        let sut = root.editController

        let monsterId = await root.itemController.addNew(type: .character)
        let hpEntry = ValueEntryModel(id: UUID(), name: "Lebenskraft", type: .number, value: "40")
        sut.add(entry: hpEntry, itemId: monsterId)

        let playerId = await root.itemController.addNew(type: .character)
        let linkText = root.itemController.itemOrEmpty(for: monsterId).url(linkNumber: 0, entryId: hpEntry.id)
        let aktuelleEntry = ValueEntryModel(id: UUID(), name: "Aktuelle", type: .number, value: linkText)
        sut.add(entry: aktuelleEntry, itemId: playerId)

        // Matches what a real joined player's device actually has set —
        // `AdventureRootModel.startGame()` (called from both `startMaster()`
        // and `GameRootModel.joinGame(for:)`) flips this true for every
        // sibling module root, `CharacterRPG` included.
        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        // Before any edit: the stepper must start from the real resolved
        // current value (40), not the old naive-split "0".
        #expect(sut.entryValueAsNumber(itemId: playerId, entryId: aktuelleEntry.id) == 40)

        // The player takes 15 damage.
        sut.updateValue(itemId: playerId, entryId: aktuelleEntry.id, number: 25)

        #expect(sut.entryValueAsNumber(itemId: playerId, entryId: aktuelleEntry.id) == 25)

        let gameEntry = try #require(
            (root.itemController.itemDataModel.gameItemData[playerId] as? ValueModel)?[aktuelleEntry.id]
        )
        #expect(gameEntry.value != linkText)

        // What actually gets sent to the master (`SheetEntryView`'s
        // `updateHandler` calls this immediately after the write above) must
        // carry the new value, and the master's own resolution engine must
        // recompute the same 25 from it — proving the full round trip, not
        // just this device's own read-back.
        let update = try #require(sut.gameValueEntryUpdate(itemId: playerId, entryId: aktuelleEntry.id))
        let decoded = try #require(GameValueEntryUpdate.decodeData(of: update.data))
        #expect(decoded.value == gameEntry.value)
        let resent = ValueEntryModel(id: aktuelleEntry.id, name: decoded.name, type: aktuelleEntry.type, value: decoded.value)
        let resolved = try #require(root.linkController.calculate(entry: resent))
        #expect(Double(resolved) == 25)
    }

    /// See CODE_AUDIT_Game §5.3: HP and other tracked values are frequently
    /// grouped, not top-level — before the fix, `gameValueEntryUpdate` named
    /// the *group* as the wire message's id, which the receiver's sender
    /// guard (`message.id == playerCharacterId`) always rejected, so a
    /// grouped value's edits never reached the master at all.
    @Test func groupedValueEntryUpdateNamesTheRootAndAppliesToTheNestedEntry() async throws {
        let root = Self.makeRoot()
        let sut = root.editController

        let playerId = await root.itemController.addNew(type: .character)
        let groupEntryId = await sut.addNewGroup(itemId: playerId)
        let groupId = try #require(root.itemController.itemOrEmpty(for: playerId)[groupEntryId].valueId)

        let hpEntry = ValueEntryModel(id: UUID(), name: "Lebenskraft", type: .number, value: "40")
        sut.add(entry: hpEntry, itemId: groupId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        sut.updateValue(itemId: groupId, entryId: hpEntry.id, number: 25)

        // The wire message must name the root Character, not the group —
        // that's what the receive-side sender guard checks against.
        let update = try #require(sut.gameValueEntryUpdate(itemId: groupId, entryId: hpEntry.id))
        #expect(update.id == playerId)

        let decoded = try #require(GameValueEntryUpdate.decodeData(of: update.data))
        #expect(decoded.characterId == playerId)
        #expect(decoded.path != nil)

        // The master applies it and it must land on the nested entry inside
        // the group, not silently no-op against the root's own top-level
        // entries (which don't contain this entryId at all).
        let gameController = root.gameController
        #expect(gameController.applyGameValueEntryUpdate(decoded))
        let appliedGroup = try #require(gameController.gameModel.itemData[groupId] as? ValueModel)
        // Same base|modifier delta convention `updateValue(number:)` used
        // above (see `EditController.resolvedBaseAndCurrent`) — resolve
        // through the link pipeline the same way `gameEntryDisplayValue`
        // does, rather than asserting the raw stored string.
        #expect(appliedGroup[hpEntry.id].value != hpEntry.value)
        #expect(gameController.gameEntryDisplayValue(characterId: groupId, entryId: hpEntry.id) == "25")
    }

    /// The standalone entry editor (`EntryEditorHeaderView`) always persists,
    /// even while a game is running — unlike `updateValue`'s live in-game quick
    /// editor above, which stays memory-only except for its own explicit,
    /// entry-scoped force-persist (`saveGameDataToPermanent`).
    @Test func entryStructuralEditPersistsDuringGameWhenForceSaved() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let entry = ValueEntryModel(id: UUID(), name: "Note", type: .text, value: "old")
        sut.add(entry: entry, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        sut.update(itemId: itemId, entryId: entry.id, name: "Renamed", content: "new content", forceSave: true)

        let permanent = try #require(root.itemController.itemSync(for: itemId, noGame: true))
        let updatedEntry = try #require(permanent.entries.first(where: { $0.id == entry.id }))
        #expect(updatedEntry.name == "Renamed")
        #expect(updatedEntry.content == "new content")
    }

    /// Regression test: an edit made through one `SheetRootModel` instance (e.g.
    /// the standalone item editor's singleton) tells its counterpart instance
    /// (e.g. the live game view's own instance) that this item may have
    /// changed, so it can catch up — via the direct `sheetRootModel` /
    /// `gameSheetRootModel` link on `ItemEditorModel`, not a general registry.
    /// Each instance owns a materialized `SheetModel` tree that only resyncs
    /// itself in response to its own local edit flow (see `Docu/SHEETS.md`);
    /// `syncCounterpart()` is what closes that gap between the two slots.
    @Test func editorEditNotifiesGameCounterpartSheet() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        sut.reset(name: "Original Name", itemId: itemId)

        let rootManager = try #require(root.rootManager)
        let editorSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: true
        )
        let gameSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: false
        )
        // syncCounterpart() looks the other side up through these two named
        // slots — not a registry — so the test must occupy them exactly like
        // production code does (see CharacterRootModel.setUp()).
        root.editController.editorModel.sheetRootModel = editorSheet
        root.editController.editorModel.gameSheetRootModel = gameSheet

        #expect(editorSheet.sheetModel.name == "Original Name")
        #expect(gameSheet.sheetModel.name == "Original Name")

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        // Edit through the shared editor controller — mirroring the standalone
        // item editor's `forceSave: true` — then reconcile the editor's own
        // sheet, exactly as the real editor view does right after a save.
        sut.reset(name: "Renamed mid-game", itemId: itemId, forceSave: true)
        editorSheet.updateFromRoot()
        #expect(editorSheet.sheetModel.name == "Renamed mid-game")

        // The game view's sheet only catches up once its own render loop
        // notices the pending flag (`SheetRootView`'s `.onChange`) — simulated
        // directly here, since this instance isn't attached to a live view.
        #expect(gameSheet.needsExternalReconcile)
        #expect(gameSheet.sheetModel.name == "Original Name")
        gameSheet.reconcileIfNeeded()
        #expect(gameSheet.sheetModel.name == "Renamed mid-game")
    }

    /// Regression test: a `SheetRootModel` that never calls
    /// `reconcileIfNeeded()` (e.g. because its view isn't currently on screen
    /// to trigger `.onChange`) must not do any reconcile work in response to
    /// its counterpart's edit — that's exactly the redundant, invisible work
    /// that made in-game editing noticeably slow. It just remembers it's stale
    /// via `needsExternalReconcile` until something actually asks it to catch up.
    @Test func gameSheetStaysUnreconciledUntilAskedToCatchUp() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        sut.reset(name: "Original Name", itemId: itemId)

        let rootManager = try #require(root.rootManager)
        let editorSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: true
        )
        let gameSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: false
        )
        root.editController.editorModel.sheetRootModel = editorSheet
        root.editController.editorModel.gameSheetRootModel = gameSheet

        sut.reset(name: "Renamed", itemId: itemId)
        editorSheet.updateFromRoot()

        // Never call gameSheet.reconcileIfNeeded() — simulating a game view
        // that isn't currently rendering (e.g. a different tab/window).
        #expect(gameSheet.sheetModel.name == "Original Name")
        #expect(gameSheet.needsExternalReconcile)
    }

    /// Regression test: editing character A must have zero effect on a
    /// counterpart `SheetRootModel` currently showing an unrelated character B
    /// — `syncFrom(itemId:)` only marks the flag when the ids actually match.
    @Test func editDoesNotAffectCounterpartShowingADifferentCharacter() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemIdA = await root.itemController.addNew(type: .character)
        let itemIdB = await root.itemController.addNew(type: .character)
        sut.reset(name: "Character A", itemId: itemIdA)
        sut.reset(name: "Character B", itemId: itemIdB)

        let rootManager = try #require(root.rootManager)
        let gameSheetA = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemIdA,
            isEditor: false
        )
        let editorSheetB = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemIdB,
            isEditor: true
        )
        root.editController.editorModel.gameSheetRootModel = gameSheetA
        root.editController.editorModel.sheetRootModel = editorSheetB

        // Edit character A through the game view's own sheet.
        sut.reset(name: "Renamed A", itemId: itemIdA)
        gameSheetA.updateFromRoot()

        // The editor's sheet is showing a completely different character (B)
        // — it must not be marked as needing a reconcile at all.
        #expect(!editorSheetB.needsExternalReconcile)
        #expect(editorSheetB.sheetModel.name == "Character B")
    }

    /// Regression test: `remove(itemId:entryId:)`/`move(itemId:entryId:up:)` —
    /// previously the only entry mutators with no `forceSave` parameter at all
    /// — now persist when the standalone editor is the one performing them,
    /// exactly like `update(itemId:entryId:...)` already does.
    @Test func removeAndMoveEntryPersistDuringGameWhenForceSaved() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let entryA = ValueEntryModel(id: UUID(), name: "A", type: .text, value: "1")
        let entryB = ValueEntryModel(id: UUID(), name: "B", type: .text, value: "2")
        sut.add(entry: entryA, itemId: itemId)
        sut.add(entry: entryB, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        sut.move(itemId: itemId, entryId: entryB.id, up: true, forceSave: true)
        var permanent = try #require(root.itemController.itemSync(for: itemId, noGame: true))
        #expect(permanent.entries.map(\.id) == [entryB.id, entryA.id])

        sut.remove(itemId: itemId, entryId: entryA.id, forceSave: true)
        permanent = try #require(root.itemController.itemSync(for: itemId, noGame: true))
        #expect(permanent.entries.map(\.id) == [entryB.id])
    }

    /// Regression test: `SheetRootModel.removeEntry`/`moveEntry(entryModel:in:up:)`
    /// previously never called `updateParent`/`updateFromRoot` at all, so
    /// deleting or reordering an entry through the editor never reconciled the
    /// game view's counterpart sheet — even after the domain data changed
    /// correctly. This directly reproduces the reported "delete an entry did
    /// not update the sync" bug.
    @Test func removeAndMoveEntryReconcileGameCounterpartSheet() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let entryA = ValueEntryModel(id: UUID(), name: "A", type: .text, value: "1")
        let entryB = ValueEntryModel(id: UUID(), name: "B", type: .text, value: "2")
        sut.add(entry: entryA, itemId: itemId)
        sut.add(entry: entryB, itemId: itemId)

        let rootManager = try #require(root.rootManager)
        let editorSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: true
        )
        let gameSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: false
        )
        root.editController.editorModel.sheetRootModel = editorSheet
        root.editController.editorModel.gameSheetRootModel = gameSheet

        #expect(editorSheet.sheetModel.entries.count == 2)
        #expect(gameSheet.sheetModel.entries.count == 2)

        let entryModel = try #require(editorSheet.sheetModel.entries.first { $0.source.entryId == entryA.id })
        editorSheet.removeEntry(entryModel: entryModel, from: editorSheet.sheetModel)

        #expect(editorSheet.sheetModel.entries.count == 1)
        #expect(gameSheet.needsExternalReconcile)
        gameSheet.reconcileIfNeeded()
        #expect(gameSheet.sheetModel.entries.count == 1)
    }

    /// Regression test: CharacterRPG's live game view is deliberately treated
    /// as an editor too (`isGameEditor: true`, see
    /// `ViewerRootView.gameSheetRootModel`) — deleting an entry FROM THE GAME
    /// VIEW must persist to the database, not stay memory-only for the
    /// session, matching "changes on character are saved." Before
    /// `isGameEditor`, only the standalone editor's `sheetRootModel`
    /// (`isEditor: true`) force-saved; the game view's own sheet always used
    /// `forceSave: false` and the deletion never reached permanent storage.
    @Test func removeEntryFromGameEditorPersistsToDatabase() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let entryA = ValueEntryModel(id: UUID(), name: "A", type: .text, value: "1")
        sut.add(entry: entryA, itemId: itemId)

        let rootManager = try #require(root.rootManager)
        let gameSheet = SheetRootModel(
            rootManager: rootManager,
            linkControllable: root.rootController.linkControllable,
            sheetControllable: root.rootController.sheetControllable,
            itemId: itemId,
            isEditor: false,
            isGameEditor: true
        )

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        let entryModel = try #require(gameSheet.sheetModel.entries.first { $0.source.entryId == entryA.id })
        gameSheet.removeEntry(entryModel: entryModel, from: gameSheet.sheetModel)

        let permanent = try #require(root.itemController.itemSync(for: itemId, noGame: true))
        #expect(permanent.entries.isEmpty)
    }

    /// Regression test: once an item is already loaded into game memory (e.g.
    /// because it was shown to players), a force-saved standalone-editor edit
    /// must update BOTH the permanent store and the game-memory snapshot.
    /// `ItemDataModel.item(for:)` always prefers game memory over the permanent
    /// store whenever an entry exists there — so leaving the stale game-memory
    /// copy untouched would make the edit invisible to every reader (the
    /// editor's own re-render, and the live game view) even though it was
    /// "successfully" persisted underneath.
    @Test func entryStructuralEditSyncsGameMemoryWhenItemAlreadyLoadedInGame() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let entry = ValueEntryModel(id: UUID(), name: "Note", type: .text, value: "old")
        sut.add(entry: entry, itemId: itemId)

        root.itemController.itemDataModel.isGameMode = true
        defer { root.itemController.itemDataModel.isGameMode = false }

        // Simulate the character having been loaded into game memory (e.g.
        // shown to players) independently of the permanent copy.
        root.itemController.replaceInGameMemory(model: root.itemController.itemOrEmpty(for: itemId).copy())

        sut.update(itemId: itemId, entryId: entry.id, name: "Renamed", content: "new content", forceSave: true)

        let permanent = try #require(root.itemController.itemSync(for: itemId, noGame: true))
        #expect(permanent.entries.first(where: { $0.id == entry.id })?.content == "new content")

        // The default read path — used by views, including the editor's own
        // re-render and the live game view — must agree with the permanent store.
        let defaultRead = try #require(root.itemController.itemSync(for: itemId))
        #expect(defaultRead.entries.first(where: { $0.id == entry.id })?.content == "new content")
    }

    @Test func linkHelpersAndSelectionEditing() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let childId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Linked Child", itemId: childId)
        let targetEntry = ValueEntryModel(id: UUID(), name: "Target", type: .text, value: "body")
        let groupEntry = ValueEntryModel(id: UUID(), name: "Group", type: .text, value: "", valueId: childId)
        sut.add(entry: targetEntry, itemId: itemId)
        sut.add(entry: groupEntry, itemId: itemId)

        #expect(sut.canAddGroups)
        #expect(sut.linkModules == [.value, .dice, .pdf, .table])
        #expect(sut.additionalEntryViewType == .inline)
        _ = sut.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: targetEntry.id, typeId: .value), entry: targetEntry, textModel: nil)
        _ = sut.linkSelectionDestination(itemRowModel: ItemRowModel(itemId: itemId, entryId: targetEntry.id, typeId: .value))
        _ = sut.quickEditorDestination(itemRowModel: ItemRowModel(itemId: itemId, typeId: .value))

        #expect(sut.canAddLink(module: .dice, entryId: nil))
        #expect(sut.canAddLink(module: .pdf, entryId: nil))
        #expect(sut.canAddLink(module: .value, entryId: UUID()))
        #expect(sut.canAddLink(module: .table, entryId: UUID()))
        #expect(!sut.canAddLink(module: .value, entryId: nil))
        #expect(!sut.canAddLink(module: .table, entryId: nil))

        let folders = sut.groupFolders(itemId: itemId, sourceEntryId: targetEntry.id)
        #expect(folders.map(\.id) == [childId])
        #expect(folders.map(\.name) == ["Group"])

        let photoA = UUID()
        let photoB = UUID()
        sut.add(selection: [WindowItemSelection(itemId: photoA), WindowItemSelection(itemId: photoB)], itemId: itemId)
        let itemAfterPhotos = root.itemController.itemOrEmpty(for: itemId)
        #expect(itemAfterPhotos.photos == [photoA, photoB])
        #expect(itemAfterPhotos.photoId == photoA)

        let diceId = UUID()
        sut.add(link: "Dice", module: .dice, itemId: diceId, entryId: nil, destinationItemId: itemId, destinationEntryId: targetEntry.id)
        var target = root.itemController.itemOrEmpty(for: itemId)[targetEntry.id]
        #expect(target.diceId == diceId)
        #expect(target.type == .number)

        let pdfId = UUID()
        sut.add(link: "PDF", module: .pdf, itemId: pdfId, entryId: nil, destinationItemId: itemId, destinationEntryId: targetEntry.id)
        target = root.itemController.itemOrEmpty(for: itemId)[targetEntry.id]
        #expect(target.type == .text)
        #expect(target.value.contains("PDF"))

        let valueId = UUID()
        let valueEntryId = UUID()
        sut.add(link: "Value", module: .value, itemId: valueId, entryId: valueEntryId, destinationItemId: itemId, destinationEntryId: targetEntry.id)
        target = root.itemController.itemOrEmpty(for: itemId)[targetEntry.id]
        #expect(target.type == .number)
        #expect(target.value.contains("Value"))

        let tableId = UUID()
        let tableEntryId = UUID()
        sut.add(link: "Table", module: .table, itemId: tableId, entryId: tableEntryId, destinationItemId: itemId, destinationEntryId: targetEntry.id)
        target = root.itemController.itemOrEmpty(for: itemId)[targetEntry.id]
        #expect(target.name.contains("Table"))

        let previousName = target.name
        sut.add(link: "Ignored", module: .table, itemId: UUID(), entryId: nil, destinationItemId: itemId, destinationEntryId: targetEntry.id)
        target = root.itemController.itemOrEmpty(for: itemId)[targetEntry.id]
        #expect(target.name == previousName)
    }

    @Test func removeDiceUnlinksWithoutChangingValueType() async throws {
        let root = Self.makeRoot()
        let sut = root.editController
        let itemId = await root.itemController.addNew(type: .character)
        let entry = ValueEntryModel(id: UUID(), name: "Target", type: .text, value: "body")
        sut.add(entry: entry, itemId: itemId)

        let diceId = UUID()
        sut.add(link: "Dice", module: .dice, itemId: diceId, entryId: nil, destinationItemId: itemId, destinationEntryId: entry.id)
        var target = root.itemController.itemOrEmpty(for: itemId)[entry.id]
        #expect(target.diceId == diceId)
        #expect(target.type == .number)

        // When: unlinking. The value type set by `add(link:...)` is left
        // untouched — only the diceId itself is cleared.
        sut.removeDice(itemId: itemId, entryId: entry.id)
        target = root.itemController.itemOrEmpty(for: itemId)[entry.id]
        #expect(target.diceId == nil)
        #expect(target.type == .number)

        // A second removal (nothing left to unlink) and an unknown item are
        // both no-ops rather than crashing or writing a spurious undo step.
        sut.removeDice(itemId: itemId, entryId: entry.id)
        sut.removeDice(itemId: UUID(), entryId: entry.id)
        target = root.itemController.itemOrEmpty(for: itemId)[entry.id]
        #expect(target.diceId == nil)
    }

    // MARK: - willDeleteChildren (called from delete)

    @Test func deleteNonFolderContainerClearsGroupIdOnChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Create a parent item and a group child
        let parentId = await root.itemController.addNew(type: .item)
        let childId = await sut.addNewGroup(itemId: parentId)

        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == childId }))
        let groupItemId = try #require(groupEntry.valueId)

        // Precondition: child has groupId set
        let childBefore = root.itemController.itemOrEmpty(for: groupItemId)
        #expect(childBefore.groupId == parentId)

        // Delete the parent (non-folder)
        await sut.delete(itemId: parentId)

        // groupId on the child must be cleared
        let childAfter = root.itemController.itemOrEmpty(for: groupItemId)
        #expect(childAfter.groupId == nil)
        // New behavior: delete() resets displayState to 0 (unhides group children)
        #expect(childAfter.displayState == 0)
    }

    // MARK: - willRestore

    @Test func restoreGroupItemClearsGroupIdWhenGroupDeleted() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Create parent and child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Mark parent for deletion using markForDeletion (new behavior)
        sut.markForDeletion(itemId: parentId)

        // Manually set the child back to deleted so restore can run
        let child = root.itemController.itemOrEmpty(for: childId)
        child.displayState = 2
        root.itemController.replace(model: child, isInsert: false)

        // Verify child has groupId pointing to deleted parent
        #expect(child.groupId == parentId)

        // Restore the child
        sut.restore(itemId: childId)

        let restoredChild = root.itemController.itemOrEmpty(for: childId)
        #expect(restoredChild.displayState == 0)
        
        // The willRestore implementation (line 361) checks if groupId parent is deleted and clears it
        // This is the CORRECT behavior - groupId should be nil when parent is deleted
        #expect(restoredChild.groupId == nil)
    }

    @Test func restoreGroupItemKeepsGroupIdWhenGroupAlive() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Create parent and child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        // Soft-delete only the child
        let child = root.itemController.itemOrEmpty(for: childId)
        child.displayState = 2
        root.itemController.replace(model: child, isInsert: false)

        // Restore the child
        sut.restore(itemId: childId)

        let restoredChild = root.itemController.itemOrEmpty(for: childId)
        #expect(restoredChild.displayState == 0)
        // Parent is alive → groupId stays
        #expect(restoredChild.groupId == parentId)
    }

    // MARK: - isOrphanedHidden

    @Test func isOrphanedHiddenReturnsTrueWhenHiddenWithNoParentAndNoGroup() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.displayState = 1
        item.parentId = nil
        item.groupId = nil
        root.itemController.replace(model: item, isInsert: false)

        let result = sut.isOrphanedHidden(itemId: itemId)
        #expect(result == true)
    }

    @Test func isOrphanedHiddenReturnsFalseWhenGroupIdIsSet() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // addNewGroup produces a hidden item with groupId set — must NOT be considered orphaned
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let result = sut.isOrphanedHidden(itemId: childId)
        #expect(result == false)
    }

    @Test func isOrphanedHiddenReturnsFalseWhenVisible() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        // displayState 0 = visible
        let result = sut.isOrphanedHidden(itemId: itemId)
        #expect(result == false)
    }

    // MARK: - parentFolder

    @Test func parentFolderResolvesGroupIdFirst() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let folder = sut.parentFolder(itemId: childId)
        try #require(folder != nil)
        #expect(folder!.id == parentId)
    }

    @Test func parentFolderFallsBackToParentIdWhenNoGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        let child = root.itemController.itemOrEmpty(for: childId)
        child.parentId = folderId
        child.groupId = nil
        root.itemController.replace(model: child, isInsert: false)

        let folder = sut.parentFolder(itemId: childId)
        try #require(folder != nil)
        #expect(folder!.id == folderId)
    }

    /// Regression test: `parentFolder(itemId:)` still falls back to `parentId`
    /// (a value entry directly on a character can sit inside a library
    /// folder), but `isValueGroupParent(itemId:)` must say `false` in that
    /// case — that's what disables "Move out to X" in the context menu for a
    /// root-level character value entry, since it has no value-group to move
    /// back out to (see `SheetContextMenuView.moveOutOfGroupButton`).
    @Test func isValueGroupParentIsFalseWhenParentFolderFallsBackToParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        let childId = await root.itemController.addNew(type: .item)
        let child = root.itemController.itemOrEmpty(for: childId)
        child.parentId = folderId
        child.groupId = nil
        root.itemController.replace(model: child, isInsert: false)

        #expect(sut.parentFolder(itemId: childId) != nil)
        #expect(!sut.isValueGroupParent(itemId: childId))
    }

    /// Regression test: when `parentFolder(itemId:)` resolves through a real
    /// value-group (`groupId`), `isValueGroupParent(itemId:)` must say `true`
    /// — "Move out to X" stays enabled for an entry actually inside a group.
    @Test func isValueGroupParentIsTrueWhenParentFolderResolvesGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        #expect(sut.parentFolder(itemId: childId) != nil)
        #expect(sut.isValueGroupParent(itemId: childId))
    }

    @Test func parentFolderReturnsNilWhenNeitherGroupIdNorParentId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let folder = sut.parentFolder(itemId: itemId)
        #expect(folder == nil)
    }

    // MARK: - duplicate with groups (groupId propagation)

    @Test func duplicateWithGroupsSetsGroupIdOnCopies() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Build: parent → group entry → child
        let parentId = await root.itemController.addNew(type: .item)
        let entryId = await sut.addNewGroup(itemId: parentId)
        let parent = root.itemController.itemOrEmpty(for: parentId)
        let groupEntry = try #require(parent.entries.first(where: { $0.id == entryId }))
        let childId = try #require(groupEntry.valueId)

        let copiedId = await sut.duplicate(itemId: parentId, withCopy: true)
        let copiedParent = root.itemController.itemOrEmpty(for: copiedId)
        #expect(copiedParent.id != parentId)
        #expect(copiedParent.groupId == nil)

        // The copied group child must point to the copy, not the original
        let copiedEntry = try #require(copiedParent.entries.first)
        let copiedChildId = try #require(copiedEntry.valueId)
        #expect(copiedChildId != childId)

        let copiedChild = root.itemController.itemOrEmpty(for: copiedChildId)
        #expect(copiedChild.groupId == copiedId)
        #expect(copiedChild.groupId != parentId)
    }

    // MARK: - addItem (folder membership + parentId)

    @Test func addItemSetsParentIdAndFolderContainsAllChildren() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        // Empty folder — no children yet
        let folderId = await root.itemController.addNew(type: .folder)
        let emptyFolder = root.itemController.itemOrEmpty(for: folderId)
        #expect(emptyFolder.entries.isEmpty)

        // Add item1 → folder must list it and parentId must be set
        let item1Id = await root.itemController.addNew(type: .item)
        sut.addItem(itemId: item1Id, parentId: folderId)

        let item1 = root.itemController.itemOrEmpty(for: item1Id)
        #expect(item1.parentId == folderId)

        let folderAfterItem1 = root.itemController.itemOrEmpty(for: folderId)
        #expect(folderAfterItem1.entries.contains(where: { $0.childId == item1Id }))

        // Create item2 but do NOT add it yet
        let item2Id = await root.itemController.addNew(type: .item)

        // Add item3 before item2 to verify out-of-order insertion still works
        let item3Id = await root.itemController.addNew(type: .item)
        sut.addItem(itemId: item3Id, parentId: folderId)

        // Now add the previously skipped item2
        sut.addItem(itemId: item2Id, parentId: folderId)

        // All three must have parentId pointing to the folder
        let finalItem1 = root.itemController.itemOrEmpty(for: item1Id)
        let finalItem2 = root.itemController.itemOrEmpty(for: item2Id)
        let finalItem3 = root.itemController.itemOrEmpty(for: item3Id)

        #expect(finalItem1.parentId == folderId)
        #expect(finalItem2.parentId == folderId)
        #expect(finalItem3.parentId == folderId)

        // Folder entries must contain all three items
        let finalFolder = root.itemController.itemOrEmpty(for: folderId)
        #expect(finalFolder.entries.count == 3)
        #expect(finalFolder.entries.contains(where: { $0.childId == item1Id }))
        #expect(finalFolder.entries.contains(where: { $0.childId == item2Id }))
        #expect(finalFolder.entries.contains(where: { $0.childId == item3Id }))
    }

    // MARK: - delete / restore round-trip

    @Test func deleteAndRestorePlainItem() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "TestItem", itemId: itemId)

        // Use markForDeletion to set displayState = 2
        sut.markForDeletion(itemId: itemId)
        let deleted = root.itemController.itemOrEmpty(for: itemId)
        #expect(deleted.displayState == 2)

        sut.restore(itemId: itemId)
        let restored = root.itemController.itemOrEmpty(for: itemId)
        #expect(restored.displayState == 0)
        #expect(restored.parentId == nil)
        #expect(restored.groupId == nil)
    }

    // MARK: - duplicate(item:) — shared behaviour with AudioRPG

    @Test("Duplicating a normal item copies all properties except id; name gets Copy suffix; parentId cleared")
    func duplicatingNormalItemCopiesAllPropertiesExceptId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.reset(description: "A brave hero", itemId: itemId)
        sut.reset(tags: ["warrior", "brave"], itemId: itemId)
        let original = root.itemController.itemOrEmpty(for: itemId)

        let before = captureIds(root)
        await sut.duplicate(item: original)
        let dupId = try await requireSingleNewId(before: before, root: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.id != original.id)
        #expect(dup.name.hasSuffix("Copy"))
        #expect(dup.description == original.description)
        #expect(dup.tags == original.tags)
        #expect(dup.category == original.category)
        #expect(dup.displayState == original.displayState)
        #expect(dup.parentId == nil)
        #expect(dup.groupId == nil)
    }

    @Test("Duplicating a collection copies all properties; entries keep references to the same child items")
    func duplicatingCollectionCopiesAllPropertiesAndKeepsEntryReferences() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let collectionId = await root.itemController.addNew(type: .collection)
        sut.reset(name: "My Collection", itemId: collectionId)
        sut.reset(tags: ["heroes"], itemId: collectionId)
        let memberId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: memberId)
        sut.addGroup(itemId: collectionId, childId: memberId)

        let original = root.itemController.itemOrEmpty(for: collectionId)
        try #require(original.entries.count == 1)

        let before = captureIds(root)
        await sut.duplicate(item: original)
        let dupId = try await requireSingleNewId(before: before, root: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.id != collectionId)
        #expect(dup.name.hasSuffix("Copy"))
        #expect(dup.category == original.category)
        #expect(dup.tags == original.tags)
        #expect(dup.entries.count == original.entries.count)
        // Entries are references — both collections point to the same member
        #expect(dup.entries.map(\.childId) == original.entries.map(\.childId))
    }

    @Test("Duplicating a folder creates a new folder with independently duplicated children — new child IDs, correct parentId")
    func duplicatingFolderDuplicatesChildrenIntoNewFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        sut.reset(name: "Folder A", itemId: folderId)
        let child1Id = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character 1", itemId: child1Id)
        sut.addItem(itemId: child1Id, parentId: folderId)
        let child2Id = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character 2", itemId: child2Id)
        sut.addItem(itemId: child2Id, parentId: folderId)

        let original = root.itemController.itemOrEmpty(for: folderId)
        try #require(original.entries.count == 2)

        let before = captureIds(root)
        await sut.duplicate(item: original)
        let newIds = captureIds(root).subtracting(before)

        let dupFolderId = try #require(firstId(in: newIds, of: root) { $0.category == .folder })
        let dupFolder = root.itemController.itemOrEmpty(for: dupFolderId)
        #expect(dupFolder.id != folderId)
        #expect(dupFolder.name.hasSuffix("Copy"))
        #expect(dupFolder.category == .folder)
        #expect(dupFolder.parentId == original.parentId)
        #expect(dupFolder.entries.count == 2)

        // New folder must reference new children, not the originals
        let dupChildIds = Set(dupFolder.entries.map(\.childId))
        #expect(!dupChildIds.contains(child1Id))
        #expect(!dupChildIds.contains(child2Id))
        for childId in dupChildIds {
            let child = root.itemController.itemOrEmpty(for: childId)
            #expect(child.parentId == dupFolderId)
        }
    }

    @Test("Duplicating an item inside a folder: duplicate keeps the same parentId and is added to the parent folder")
    func duplicatingItemInFolderPreservesParentAndIsAddedToFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        sut.reset(name: "Folder A", itemId: folderId)
        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.addItem(itemId: itemId, parentId: folderId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.parentId == folderId)

        let before = captureIds(root)
        await sut.duplicate(item: item)
        let dupId = try await requireSingleNewId(before: before, root: root)
        let dup = root.itemController.itemOrEmpty(for: dupId)

        #expect(dup.parentId == folderId)
        let folder = root.itemController.itemOrEmpty(for: folderId)
        #expect(folder.entries.contains(where: { $0.childId == dupId }))
    }

    @Test("Duplicating a collection member adds the new item as a child reference in that collection")
    func duplicatingCollectionMemberAddsNewReferenceToCollection() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let collectionId = await root.itemController.addNew(type: .collection)
        sut.reset(name: "My Collection", itemId: collectionId)
        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.addGroup(itemId: collectionId, childId: itemId)

        let collection = root.itemController.itemOrEmpty(for: collectionId)
        try #require(collection.entries.count == 1)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let before = captureIds(root)
        await sut.duplicate(item: item)
        let dupId = try await requireSingleNewId(before: before, root: root)

        let updatedCollection = root.itemController.itemOrEmpty(for: collectionId)
        #expect(updatedCollection.entries.count == 2)
        #expect(updatedCollection.entries.contains(where: { $0.childId == dupId }))
    }

    // MARK: - duplicate(item:) — CharacterRPG-specific: group sub-items

    @Test("Duplicating an item with group sub-items copies the groups; new groups have groupId pointing to the duplicate")
    func duplicatingItemWithGroupsCopiesGroupsWithNewGroupId() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let itemId = await root.itemController.addNew(type: .item)
        let entry1Id = await sut.addNewGroup(itemId: itemId)
        let entry2Id = await sut.addNewGroup(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let entry1 = try #require(item.entries.first(where: { $0.id == entry1Id }))
        let originalGroup1Id = try #require(entry1.valueId)
        let entry2 = try #require(item.entries.first(where: { $0.id == entry2Id }))
        let originalGroup2Id = try #require(entry2.valueId)

        let before = captureIds(root)
        await sut.duplicate(item: item)
        let newIds = captureIds(root).subtracting(before)

        // The main duplicate has groupId == nil; group copies have groupId set
        let dupItemId = try #require(firstId(in: newIds, of: root) { $0.groupId == nil })
        let dupItem = root.itemController.itemOrEmpty(for: dupItemId)
        #expect(dupItem.id != itemId)
        #expect(dupItem.name.hasSuffix("Copy"))
        #expect(dupItem.entries.count == 2)

        for entry in dupItem.entries {
            let newGroupId = try #require(entry.valueId)
            // Each group is a new item, not the original
            #expect(newGroupId != originalGroup1Id)
            #expect(newGroupId != originalGroup2Id)
            let newGroup = root.itemController.itemOrEmpty(for: newGroupId)
            // New group's groupId points to the duplicate, not the original
            #expect(newGroup.groupId == dupItemId)
            #expect(newGroup.groupId != itemId)
            #expect(newGroup.displayState == 1)
        }
    }

    @Test("Duplicating an item with groups inside a folder: groups are copied and item is added to the same folder")
    func duplicatingItemWithGroupsInFolderCopiesGroupsAndAddsToFolder() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.editController

        let folderId = await root.itemController.addNew(type: .folder)
        sut.reset(name: "Folder A", itemId: folderId)
        let itemId = await root.itemController.addNew(type: .item)
        sut.reset(name: "Character A", itemId: itemId)
        sut.addItem(itemId: itemId, parentId: folderId)
        let entryId = await sut.addNewGroup(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        let groupEntry = try #require(item.entries.first(where: { $0.id == entryId }))
        let originalGroupId = try #require(groupEntry.valueId)

        let before = captureIds(root)
        await sut.duplicate(item: item)
        let newIds = captureIds(root).subtracting(before)

        let dupItemId = try #require(firstId(in: newIds, of: root) { $0.groupId == nil })
        let dupItem = root.itemController.itemOrEmpty(for: dupItemId)

        // Duplicate is in the same folder
        #expect(dupItem.parentId == folderId)
        let folder = root.itemController.itemOrEmpty(for: folderId)
        #expect(folder.entries.contains(where: { $0.childId == dupItemId }))

        // Group is a new copy with groupId pointing to the duplicate
        let dupEntry = try #require(dupItem.entries.first)
        let newGroupId = try #require(dupEntry.valueId)
        #expect(newGroupId != originalGroupId)
        let newGroup = root.itemController.itemOrEmpty(for: newGroupId)
        #expect(newGroup.groupId == dupItemId)
    }
}
