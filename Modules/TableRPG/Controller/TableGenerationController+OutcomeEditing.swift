// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of TableGenerationController.swift, which mixed this feature in
// with the core roll/select/build-tree logic. See CODE_AUDIT_Table §9.9.
extension TableGenerationController {
    /// Opens (creating on first use) the in-memory-only sheet-editing
    /// session backing the "Edit as Sheet" outcome editor. Only sets state —
    /// the view drives the actual transition (see `TableGenerationResultView`),
    /// which pauses briefly before switching `model.isEditingOutcomeSheet`.
    ///
    /// Opens the sheet editor on a wrapping root whose one entry (its name
    /// — the editable stand-in for the root's own uneditable title, see
    /// `SimpleSheetEditingSession`) is seeded from the outcome's computed
    /// name; nested underneath it, the actual result item gets one entry
    /// per selection, so it reads like a nice, labeled value list rather
    /// than one opaque blob of combined text — one entry per result, one
    /// per table (name = that entry's own table, content = its value).
    @MainActor
    func beginEditingOutcomeSheet(model: TableGenerationModel) {
        guard model.isFullyDecided else { return }
        guard model.outcomeEditingSession == nil else { return }

        let selections = model.currentSelections
        guard !selections.isEmpty else { return }

        let session = SimpleSheetEditingSession(module: .table, name: model.root.tableName.withoutLink())
        for selection in selections {
            _ = session.editController.insertEntry(
                itemId: session.resultItemId,
                name: selection.tableName,
                content: selection.content,
                position: .end,
                // The throwaway session never runs a game; its model is memory-only anyway.
                forceSave: false
            )
        }
        // `SheetRootModel` already captured its `SheetModel` tree (with an
        // empty nested result sheet) at construction, before the seeding
        // above ran — flag it for a reconcile so the seeded rows actually
        // render the moment the sheet editor first appears, instead of
        // staying stale until some unrelated interaction happens to
        // trigger one.
        session.sheetRootModel.syncFrom(itemId: session.itemId)
        model.outcomeEditingSession = session
    }

    /// Flattens the session's current entries back into `model.editedOutcome`
    /// and leaves the sheet editor — but keeps the session itself around so
    /// reopening the editor resumes exactly where the user left off.
    @MainActor
    func endEditingOutcomeSheet(model: TableGenerationModel) {
        if let result = model.outcomeEditingSession?.resultModel {
            model.editedOutcome = flattenOutcomeText(from: result)
        }
        model.isEditingOutcomeSheet = false
    }

    /// Drops the outcome sheet-editing session entirely — nothing to tear
    /// down beyond clearing the reference, since it never touched Core Data.
    @MainActor
    func discardOutcomeSession(model: TableGenerationModel) {
        guard model.outcomeEditingSession != nil else { return }
        model.outcomeEditingSession = nil
        model.isEditingOutcomeSheet = false
    }

    /// Adds the edited outcome as a new value on the character — via the
    /// real, whole-app `RootManager` (not this session's own throwaway
    /// one), resolving Character's real `editControllable` and calling
    /// `EditControllable.addItem(sheet:forceSave:)`, returning the new value's id.
    /// Forced: "Save outcome as value" is an explicit library save, also during a game; without
    /// it the new value stayed empty and nameless in the library. See CODE_AUDIT_Edit_Save §5.9.
    /// `nil` if the real `RootManager` isn't available yet (shouldn't happen
    /// once the app has finished setup, which always completes before the
    /// generation panel can be shown) or Character's own conformer didn't
    /// create anything.
    @MainActor
    func addOutcomeToCharacter(session: SimpleSheetEditingSession) async -> UUID? {
        guard let editControllable = rootManagerBox.rootManager?.characterRoot.editControllable else { return nil }
        return await editControllable.addItem(sheet: session.sheetRootModel.sheetModel, forceSave: true)
    }

    /// Joins the result item's current entries back into the plain outcome
    /// string `model.summary` reads — mirrors the seeding in
    /// `beginEditingOutcomeSheet(model:)` symmetrically: a single row stays
    /// flat (just its content, falling back to its name if the user cleared
    /// the content), while multiple rows are each labeled with their own
    /// name so the result stays attributable to the table it came from
    /// (e.g. "Loot Table: Sword\nMonster Table: Goblin"). Based on the
    /// result item's *current* entries, not the original selection count,
    /// so it stays correct however the user reshaped the sheet (merged rows
    /// into one, split one into several, ...).
    @MainActor
    private func flattenOutcomeText(from item: SimpleModel) -> String {
        let rows = item.entries.filter { !$0.name.isEmpty || !$0.content.isEmpty }
        if rows.count <= 1 {
            guard let only = rows.first else { return "" }
            return only.content.isEmpty ? only.name : only.content
        }
        return rows
            .map { entry in entry.name.isEmpty ? entry.content : "\(entry.name): \(entry.content)" }
            .joined(separator: "\n")
    }
}
