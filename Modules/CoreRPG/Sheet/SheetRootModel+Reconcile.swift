// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    /// Re-synchronizes the currently edited parent after a module-specific bulk editor saves.
    public func updateParent() {
        guard let parentModel = editorModel.parentModel else { return }
        updateParent(parentModel)
    }

    /// Re-syncs a SheetModel tree from live data, then invalidates linkTextModel cache for any entry
    /// whose content changed (hasChanged) and clears the flag.
    func updateParent(_ parentModel: SheetModel) {
        if parentModel.source.typeId == .value {
            updateFromRoot()
            return
        }
        rootController(for: parentModel.source.typeId)?.sheetControllable.update(root: rootManager, sheetModel: parentModel, isEditor: isEditor)
        resetChangedLinkModels(in: parentModel)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
        syncCounterpart()
    }

    /// Debounced counterpart to `updateParent(_:)` for call sites that may fire once per
    /// mutated field across several sibling entries under the same parent within a single
    /// external reconcile (e.g. each entry's own `.onChange(of: name/description)` in
    /// `SheetEntryView`), coalescing them into one reconcile of `parentModel` instead of
    /// one per changed field. See CODE_AUDIT_Sheet §7.1.
    func scheduleParentReconcile(_ parentModel: SheetModel) {
        let parentId = parentModel.id
        pendingParentReconcileTasks[parentId]?.cancel()
        pendingParentReconcileTasks[parentId] = delayedTask(.settleDelay) { [self] in
            pendingParentReconcileTasks[parentId] = nil
            updateParent(parentModel)
        }
    }

    /// Updates from the root SheetModel down - use when changes may affect calculated values throughout the tree
    public func updateFromRoot() {
        performReconcile()
        syncCounterpart()
    }

    func performReconcile() {
        rootController(for: sheetModel.source.typeId)?.sheetControllable.update(root: rootManager, sheetModel: sheetModel, isEditor: isEditor)
        resetChangedLinkModels(in: sheetModel)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    private func resetChangedLinkModels(in sheetModel: SheetModel) {
        if sheetModel.hasChanged {
            let lookupId = sheetModel.source.entryId ?? sheetModel.source.itemId
            // Keys must match the ones `SheetView` renders with: `.item` for the header
            // name, `.itemContent` for the description row below it.
            resetLinkText([.item], sourceId: sheetModel.source.itemId, text: sheetModel.name)
            resetLinkText([.itemContent], sourceId: sheetModel.source.itemId, text: sheetModel.description)
            resetLinkText([.entryContent], sourceId: lookupId, text: sheetModel.description)
            sheetModel.hasChanged = false
        }
        for entry in sheetModel.entries {
            if entry.hasChanged {
                let lookupId = entry.source.entryId ?? entry.source.itemId
                resetLinkText([.entry], sourceId: lookupId, text: entry.name)
                resetLinkText([.entryContent], sourceId: lookupId, text: entry.description)
                entry.hasChanged = false
            }
            for subEntry in entry.entries {
                resetChangedLinkModels(in: subEntry)
            }
        }
    }
}
