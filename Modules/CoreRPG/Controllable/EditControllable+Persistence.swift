// @copyright André Trettin

import SwiftUI

// Saving, undo recording, the forced write of a game edit onto the library, and the link
// register and tag counts that follow a save. Split from EditControllable.swift
// (CODE_AUDIT_Edit_Save §9.8).

// MARK: - Controller Maintenance

public extension EditControllable {
    @MainActor func editModel(for itemId: UUID) -> Model? {
        return itemControllable.itemSync(for: itemId)?.copy() as? Model
    }

    /// Clears any editor state still referencing a deleted item, so a stale/removed model
    /// doesn't linger in the header editor, the group/sheet editor, or the item link cache.
    /// Only the deleted item's undo changes go: clearing the whole history when the deleted
    /// item was the current one wiped every other item's steps, and a step left for it would
    /// insert it again. See CODE_AUDIT_Edit_Save §5.4.
    @MainActor func removeFromEditors(itemId: UUID) {
        editorModel.removeUndoChanges(of: itemId)
        if editorModel.currentItemId == itemId {
            editorModel.setCurrentItemId(nil)
        }
        if editorModel.sheetEditorModel.itemId == itemId {
            editorModel.sheetEditorModel.itemId = nil
            editorModel.sheetEditorModel.entryId = nil
        }
        editorModel.cacheItemListModel.reset(itemId: itemId)
    }

    /// - Parameter forcedBase: For a forced save during a game, the value the edit is diffed
    ///   against instead of the game copy (see `forcedBase(for:touching:)`).
    @MainActor func saveChanges(to newValue: Model, name: String, forceSave: Bool, forcedBase: Model? = nil) {
        // A fixed identifier: the counter logs it as public, and `name` can carry a user tag
        // ("Add <tag>"). See CODE_AUDIT_Folder §6.5.
        recordOperation("EditControllable.saveChanges(to:name:)")

        if let previous = itemControllable.itemOrEmpty(for: newValue.id).copy() as? Model {
            recordUndo(before: previous, after: newValue, scope: forceSave ? .forced : .current, title: name)
        }

        if forceSave, writeForcedEditOfGameCopy(newValue, base: forcedBase) {
            notifyPersistedGameEdit(newValue.id)
            return
        }

        // A memory-only game edit leaves the persisted link register alone: it describes the
        // library, and nothing reverted it at game end. See CODE_AUDIT_29 §5.3.
        let persists = persistsEdit(forceSave: forceSave)
        if persists {
            updateLinkRegister(to: newValue)
        }
        itemControllable.replace(model: newValue, isInsert: false, forceSave: forceSave)
        if persists {
            notifyPersistedGameEdit(newValue.id)
        }
    }

    /// Tells the running game that an edit of `itemId` persisted. See CODE_AUDIT_Edit_Save §5.24.
    @MainActor private func notifyPersistedGameEdit(_ itemId: UUID) {
        guard itemControllable.itemDataModel.isGameMode else { return }
        editorModel.persistedGameEditHandler?(itemId)
    }

    /// Records one saved change for undo: the value before and after it, and where it was
    /// written. A change of only the file leaves no step (undo never touches files).
    /// See CODE_AUDIT_Edit_Save §5.1-§5.3.
    @MainActor func recordUndo(before: Model, after: Model, scope: ItemEditUndoScope, title: String) {
        let before = before.copy()
        let after = after.copy()
        guard Model.hasUndoableChange(from: before, to: after) else { return }
        editorModel.recordUndo(
            ItemEditUndoStep.Change(itemId: after.id, before: before, after: after, scope: scope),
            title: title,
            gameGeneration: itemControllable.itemDataModel.gameGeneration
        )
    }

    /// Runs `body` as one undo step: every save it makes joins one step, so one Cmd+Z reverts
    /// the whole user action. See CODE_AUDIT_Edit_Save §5.5.
    @MainActor func asOneUndoStep<Result>(_ title: String, _ body: () -> Result) -> Result {
        editorModel.beginUndoGroup(title: title)
        defer { editorModel.endUndoGroup() }
        return body()
    }

    /// `asOneUndoStep(_:_:)` for a user action that suspends between its saves.
    @MainActor func asOneUndoStep<Result>(_ title: String, _ body: () async -> Result) async -> Result {
        editorModel.beginUndoGroup(title: title)
        defer { editorModel.endUndoGroup() }
        return await body()
    }

    /// A forced save of an item that has a game copy: `newValue` was built on that copy, so
    /// writing it whole put the game's session state (hit points, revealed values) into the
    /// library, and the library state then overwrote the game copy. Only what this edit
    /// changed goes to the library (`applyEdit`, module fields included); the game copy takes
    /// the edited value. Returns `false`, writing nothing, when the item has no game copy.
    /// See CODE_AUDIT_29 §5.2.
    ///
    /// A module whose entries are session-only content (`hasSessionOnlyEntries`, a map) takes
    /// this path during a game also without a game copy: the library gets the metadata, and the
    /// whole edit goes to game memory. See CODE_AUDIT_Edit_Save §5.13.
    ///
    /// - Parameter base: What the edit is diffed against; the game copy when `nil`.
    @MainActor func writeForcedEditOfGameCopy(_ newValue: Model, base: Model? = nil) -> Bool {
        let gameCopy = gameCopy(of: newValue.id)
        guard gameCopy != nil || (Model.hasSessionOnlyEntries && itemControllable.itemDataModel.isGameMode),
              let library = itemControllable.itemSync(for: newValue.id, noGame: true)?.copy() as? Model else { return false }
        var libraryValue = library
        libraryValue.applyEdit(from: base ?? gameCopy ?? library, to: newValue)
        if let stored = itemControllable.itemSync(for: newValue.id, noGame: true) as? Model {
            updateLinkRegister(to: libraryValue, from: stored)
        }
        itemControllable.replace(model: libraryValue, isInsert: false, forceSave: true, syncGameMemory: false)
        // Without a game copy, only an edit of the session-only entries goes to game memory; a
        // header edit of a map the game has not loaded makes no game copy.
        if gameCopy != nil || newValue.entries != libraryValue.entries {
            itemControllable.replaceInGameMemory(model: newValue)
        }
        return true
    }

    /// The diff base of a forced field edit during a game: the game copy with the touched fields
    /// set to the library's values. When the game copy already had the value the user entered
    /// (changed in the game view, memory-only), the edit diffed against the game copy changed
    /// nothing and was dropped although the library still had the old value.
    /// `nil` without a game copy. See CODE_AUDIT_Edit_Save §5.14.
    @MainActor func forcedBase(for itemId: UUID, touching touch: (inout Model, Model) -> Void) -> Model? {
        guard let gameCopy = gameCopy(of: itemId),
              let library = itemControllable.itemSync(for: itemId, noGame: true) as? Model else { return nil }
        var base = gameCopy.copy()
        touch(&base, library)
        return base
    }

    /// Whether an edit with `forceSave` reaches the library (and so the shared link register and
    /// tag counts): always outside a game, only when forced during one.
    @MainActor func persistsEdit(forceSave: Bool) -> Bool {
        forceSave || !itemControllable.itemDataModel.isGameMode
    }

    /// The game-memory copy readers see for `itemId`, when it is not the library instance itself.
    @MainActor func gameCopy(of itemId: UUID) -> Model? {
        guard let current = itemControllable.itemSync(for: itemId) as? Model,
              let library = itemControllable.itemSync(for: itemId, noGame: true) as? Model,
              (current as AnyObject) !== (library as AnyObject)
        else { return nil }
        return current
    }

    /// Brings the link register in line with `newValue`: the links the item's stored value had and
    /// `newValue` has not are removed, the new ones added. Shared by `saveChanges` and undo/redo,
    /// which restore a stored value and must leave the register as a save would.
    /// See CODE_AUDIT_28 §5.3.
    @MainActor func updateLinkRegister(to newValue: Model) {
        updateLinkRegister(to: newValue, from: itemControllable.itemSync(for: newValue.id) as? Model)
    }

    /// `updateLinkRegister(to:)` against an explicit previous value (the library copy for a
    /// forced write during a game).
    @MainActor func updateLinkRegister(to newValue: Model, from previous: Model?) {
        if let previous {
            let (added, removed) = newValue.changedLinkRegisterModels(oldValue: previous)

            linkRegisterController.deregister(links: removed)
            linkRegisterController.register(links: added)
        } else {
            let added = newValue.linkRegisterModels
            linkRegisterController.register(links: added)
        }
    }

    /// Brings the tag counts in line with `newValue`. A trashed item counts no tags (trashing
    /// removes them, restoring adds them back), so the difference is taken between what the stored
    /// value counts and what `newValue` counts. Used by undo/redo; the edits that change tags
    /// adjust the counts themselves. See CODE_AUDIT_28 §5.3.
    @MainActor func updateTagCounts(to newValue: Model) {
        updateTagCounts(to: newValue, from: itemControllable.itemSync(for: newValue.id) as? Model)
    }

    /// `updateTagCounts(to:)` against an explicit previous value (the library copy for a forced
    /// write during a game). See CODE_AUDIT_Edit_Save §5.7.
    @MainActor func updateTagCounts(to newValue: Model, from previous: Model?) {
        let counted: (Model?) -> Set<String> = { model in
            guard let model, !model.isHidden else { return [] }
            return Set(model.tags)
        }
        let before = counted(previous)
        let after = counted(newValue)
        updateTags(addedTags: Array(after.subtracting(before)), removedTags: Array(before.subtracting(after)))
    }

    @MainActor func save(updated: Model, message: String, forceSave: Bool, forcedBase: Model? = nil) {
        save(with: message, currentModel: updated, forceSave: forceSave, forcedBase: forcedBase)
    }

    @MainActor func setCurrentItem(to item: ItemRowTreeModel) {
        guard editorModel.sheetEditorModel.itemId != item.model.itemId else {
            editorModel.sheetEditorModel.entryId <=> item.model.entryId
            editorModel.sheetEditorModel.module = item.model.typeId
            return
        }
        guard let model = itemControllable.copy(of: item.model.itemId) as? Model else { return }
        setCurrentItem(model: model, entryId: item.model.entryId, module: item.model.typeId)
    }
    
    @MainActor func setCurrentItem(model: Model, entryId: UUID? = nil, module: NetworkModules? = nil) {
        if model.id != editorModel.sheetEditorModel.itemId {
            editorModel.cacheItemListModel.resetItemLink()
            editorModel.undoManaged.removeAll()
            editorModel.setCurrentItemId(model.id)
            editorModel.sheetEditorModel.itemId = model.id
        }
        editorModel.sheetEditorModel.entryId <=> entryId
        editorModel.sheetEditorModel.module = module ?? itemControllable.config.module
    }

    /// - Parameter forcedBase: see `saveChanges(to:name:forceSave:forcedBase:)`. With one, the
    ///   save goes through although `currentModel` equals the game copy: the library may not.
    ///   See CODE_AUDIT_Edit_Save §5.14.
    @MainActor func save(with name: String, currentModel: Model, forceSave: Bool, forcedBase: Model? = nil) {
        if itemControllable.isEqual(with: currentModel) {
            guard forceSave, let forcedBase, !forcedBase.isEqual(other: currentModel) else { return }
        }
        // After the no-change guard: a no-op save runs no module hook. See CODE_AUDIT_Edit_Save §3.6.
        validateBeforeSave(model: currentModel)
        saveChanges(to: currentModel, name: name, forceSave: forceSave, forcedBase: forcedBase)
    }
}
