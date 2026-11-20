// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    // MARK: - Editor

    public func removeEntry(entryModel: SheetModel, from parentModel: SheetModel) {
        if entryModel.isGeneratedAnswer {
            sheetModel.aiGeneratedEntries.removeAll { $0 === entryModel }
            return
        }
        guard entryDataEditable(for: entryModel.source)?.removeEntry(source: entryModel.source, forceSave: persistsEdits) == true else { return }
        // Use source identifiers to match and remove
        parentModel.entries.removeAll(where: { entry in
            entry.source.itemId == entryModel.source.itemId &&
            entry.source.entryId == entryModel.source.entryId &&
            entry.source.typeId == entryModel.source.typeId
        })
        // Use source identifiers for linkTextModel cleanup
        if let entryId = entryModel.source.entryId {
            linkTextModel[.entry(entryId)] = nil
        } else {
            linkTextModel[.entry(entryModel.source.itemId)] = nil
        }
        updateFilteredEntries()
        updateParent(parentModel)
    }

    /// Update the sheet model after inline edits.
    ///
    /// Patches `entryModel`'s own displayed text immediately (cheap, and keeps
    /// a stepper/quick-editor feeling instant), then schedules a debounced
    /// reconcile of `parentModel` via `scheduleParentReconcile(_:)` so any
    /// *other* entry whose value formula links to this one — including one in
    /// a different group — picks up the new result. Without this, an entry's
    /// own row updated correctly but a sibling/other-group entry computed
    /// from it via a markdown link (`LinkController.calculate`) stayed stale
    /// until some unrelated reconcile happened to run.
    func updateSheetModel(entryModel: SheetModel, parentModel: SheetModel, updatedText: String) {
        entryModel.description = updatedText
        let lookupId = entryModel.source.entryId ?? entryModel.source.itemId
        linkTextModel[.entry(lookupId)]?.reset(text: entryModel.name)
        linkTextModel[.entryContent(lookupId)]?.reset(text: entryModel.description)
        scheduleParentReconcile(parentModel)
    }

    func addNewEntry(in sheetModel: SheetModel) -> UUID? {
        guard let entryId = addNewEntry(to: sheetModel.source) else { return nil }
        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }

    @MainActor func addNewGroup(in sheetModel: SheetModel) async -> UUID? {
        guard let editable = entryDataEditable(for: sheetModel.source), editable.canAddGroups else { return nil }
        let entryId = await editable.addNewGroup(itemId: sheetModel.source.itemId)

        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }

    func convertibleGroupCandidates(source: ItemRowModel) -> [FolderRepresentable] {
        guard let entryId = source.entryId, let editable = entryDataEditable(for: source) else { return [] }
        let content = editable.entryContent(itemId: source.itemId, entryId: entryId)
        var seen: Set<UUID> = []
        return LinkReplaceController.links(for: content).compactMap { link -> FolderRepresentable? in
            guard link.entryId == nil,
                  link.module == source.typeId,
                  editable.canBecomeGroup(itemId: link.itemId, in: source.itemId),
                  seen.insert(link.itemId).inserted else { return nil }
            return FolderRepresentable(id: link.itemId, name: editable.itemControllable.nameSync(itemId: link.itemId))
        }
    }

    @MainActor func convertEntryToGroup(source: ItemRowModel, existingItemId: UUID?) async -> (any ItemDataAccessible)? {
        // No `canConvertGroups` check here: the default `convertToGroup` creates nothing, so the
        // result below is `nil` for an editor without group support, and the menus already offer
        // the action only where `canConvertGroups` is true. See CODE_AUDIT_26 §5.71.
        guard let entryId = source.entryId,
              let editable = entryDataEditable(for: source) else { return nil }
        let groupId = await editable.convertToGroup(itemId: source.itemId, entryId: entryId, existingItemId: existingItemId)
        updateFromRoot()

        // The entry's rendered name now contains a freshly materialized link (or lost one).
        // A cached LinkHighlightTextModel doesn't re-scan on its own when handed new text
        // through `linkTextModel(for:text:)` (it only seeds the cache on first access), so
        // without this the row keeps rendering the pre-conversion text until its view is
        // torn down and rebuilt.
        if let entryModel = findEntryModel(entryId: entryId, in: sheetModel) {
            linkTextModel[.entry(entryId)]?.reset(text: entryModel.name)
            linkTextModel[.entryContent(entryId)]?.reset(text: entryModel.description)
        }

        // Turning an existing item into a hidden group (or creating a new hidden one) only
        // mutates that item's own fields (groupId/displayState) — it doesn't touch
        // itemDataModel.items. ListModelUpdatesViewModifier's observation stream only watches
        // that array, so it never notices, and the item lingers in the root list until an
        // unrelated search rebuilds it. Ask the list explicitly, like ListRootContextMenu's
        // move/add/remove actions already do for the same class of field-only mutation.
        rootController(for: source.typeId)?.folderListControllable.update(debounce: false)

        return editable.itemControllable.itemSync(for: groupId)
    }

    /// Re-syncs the tree after the link picker (`EditorLinkView`, opened from a row's
    /// "Add Links" context menu) wrote links into `source`'s entry. The picker goes
    /// straight through the edit controller, so unlike a link drop (`addLink(link:...)`)
    /// this model never sees the mutation on its own — see `ItemEditorModel.finishLinkSelection`.
    func updateAfterLinkSelection(source: ItemRowModel) {
        updateFromRoot()

        guard let entryId = source.entryId, let entryModel = findEntryModel(entryId: entryId, in: sheetModel) else { return }
        linkTextModel[.entry(entryId)]?.reset(text: entryModel.name)
        linkTextModel[.entryContent(entryId)]?.reset(text: entryModel.description)
    }

    private func findEntryModel(entryId: UUID, in model: SheetModel) -> SheetModel? {
        if model.source.entryId == entryId { return model }
        for entry in model.entries {
            if let found = findEntryModel(entryId: entryId, in: entry) { return found }
        }
        return nil
    }

    public func setScrollEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.editorModel.sheetEditorModel.scrollEntryId = entryId
    }

    private func addNewEntry(to source: ItemRowModel) -> UUID? {
        guard let editable = entryDataEditable(for: source) else { return nil }
        return editable.addNewEntry(itemId: source.itemId, forceSave: persistsEdits)
    }

    func update(sheetModel: SheetModel, previousEntryId: UUID?, currentEntryId: UUID?) {
        guard let previousEntryId, currentEntryId == nil, editorModel.itemId == sheetModel.source.itemId else { return }

        updateFromRoot()

        guard let entryModel = sheetModel.entries.first(where: { $0.source.entryId == previousEntryId }) else { return }
        entryModel.isEditing = false

        let lookupId = entryModel.source.entryId ?? entryModel.source.itemId
        linkTextModel[.entry(lookupId)]?.reset(text: entryModel.name)
        linkTextModel[.entryContent(lookupId)]?.reset(text: entryModel.description)
    }

    /// Set the current item in the edit controller (keeps ItemEditorModel in sync for scroll/other consumers)
    func setCurrentItem(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.setCurrentItem(to: ItemRowTreeModel(itemId: source.itemId, entryId: entryId, typeId: source.typeId))
    }
}
