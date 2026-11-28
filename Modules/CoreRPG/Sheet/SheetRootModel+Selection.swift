// @copyright André Trettin

import SwiftUI

extension SheetRootModel {
    // MARK: - Selection

    /// Exclusively selects `entryModel`, clearing whichever entry was previously selected
    /// (anywhere in the tree, including the root sheetModel itself). `parent` is threaded
    /// explicitly by the caller (who already has it in scope) rather than looked up, since
    /// SheetContextMenuView's move-up/down/into-group actions need it too.
    ///
    /// Deliberately never scrolls. Scrolling belongs solely to genuine focus activation — see
    /// each row's `onChange(of: focusedEntryId.wrappedValue)` — because `setSelected` also
    /// runs for tap-driven selection, where the tapped row is by definition already on
    /// screen. Scrolling there anyway leaves `.scrollPosition(_:anchor:)` pinned to that
    /// row's id, and that pin isn't one-shot: SwiftUI keeps re-centering on it as later,
    /// unrelated layout changes occur (e.g. expanding a link elsewhere inserts rows), which
    /// is what produced the "jumps to top and back" glitch.
    func setSelected(_ entryModel: SheetModel, parent: SheetModel) {
        if selectedEntryId == entryModel.id,
           selectedEntryModel === entryModel,
           entryModel.isSelected {
            selectedParentModel = parent
            return
        }
        if let previous = selectedEntryModel, previous !== entryModel {
            previous.isSelected = false
        } else if selectedEntryModel == nil,
                  let selectedEntryId,
                  let previous = findEntry(id: selectedEntryId, in: sheetModel),
                  previous !== entryModel {
            previous.isSelected = false
        }
        entryModel.isSelected = true
        selectedEntryId = entryModel.id
        selectedEntryModel = entryModel
        selectedParentModel = parent
    }

    /// Shared body of `SheetView`/`SheetEntryView`'s own `.onChange(of: focusedEntryId.wrappedValue)`
    /// — covers focus reaching a row without going through its tap action (e.g. Tab-key
    /// navigation, or the keyboard-arrow sync in `SheetRootView`), keeping `focusId` and
    /// `selectedId` the same regardless of how focus got here, and is the sole place that
    /// requests a scroll (see `setSelected`'s own doc for why). Callers must still guard that
    /// `focusedEntryId.wrappedValue == entryModel.id` before calling this — that comparison
    /// needs the row's own `@FocusState` binding, which this model doesn't have access to.
    /// See CODE_AUDIT §9.12.
    func handleFocusActivation(entryModel: SheetModel, parent: SheetModel) {
        if selectedEntryId != entryModel.id {
            setSelected(entryModel, parent: parent)
        }
        // The root/name-row case (entryModel is the root) has no entryId — nothing to scroll to.
        if let entryId = entryModel.source.entryId {
            setScrollEntryId(source: entryModel.source, entryId: entryId)
        }
    }

    func clearSelection() {
        guard let selectedEntryId else { return }
        if let selectedEntryModel {
            selectedEntryModel.isSelected = false
        } else {
            findEntry(id: selectedEntryId, in: sheetModel)?.isSelected = false
        }
        self.selectedEntryId = nil
        self.selectedEntryModel = nil
        self.selectedParentModel = nil
    }

    /// Whether a viewer row offers the button that opens its quick controls. The Apple TV
    /// game view only displays the sheet (it mirrors its host player's character), so it
    /// has none.
    var offersInlineEditing: Bool {
#if os(tvOS)
        !isGameEditor
#else
        true
#endif
    }

    /// Opens or closes the quick controls for an entry in a viewer sheet.
    /// Only one entry can be edited at a time.
    func toggleInlineEditing(_ entryModel: SheetModel, parent: SheetModel) {
        setSelected(entryModel, parent: parent)

        if inlineEditingEntryId == entryModel.id {
            entryModel.isEditing = false
            inlineEditingEntryModel?.isEditing = false
            inlineEditingEntryModel = nil
            inlineEditingEntryId = nil
            return
        }

        inlineEditingEntryModel?.isEditing = false
        entryModel.isEditing = true
        inlineEditingEntryModel = entryModel
        inlineEditingEntryId = entryModel.id
    }

    func updateEditType(
        _ editType: SheetModelEditType,
        for entryModel: SheetModel,
        parent: SheetModel
    ) {
        guard let entryId = entryModel.source.entryId,
              let editable = editControllable(for: entryModel.source) as? any SheetEditTypeControllable,
              editable.supportedSheetEditTypes.contains(editType),
              entryModel.editType != editType else { return }
        editable.updateSheetEditType(
            itemId: entryModel.source.itemId,
            entryId: entryId,
            editType: editType,
            forceSave: persistsEdits
        )
        entryModel.editType = editType
        updateParent(parent)
    }

    func supportedEditTypes(for source: ItemRowModel) -> [SheetModelEditType] {
        (editControllable(for: source) as? any SheetEditTypeControllable)?
            .supportedSheetEditTypes ?? []
    }

    /// First non-hidden top-level entry — used to select "into" a sheet from the sidebar list.
    var firstSelectableEntry: SheetModel? {
        sheetModel.entries.first { !$0.isHidden && !$0.isGeneratedHidden }
    }

    /// Selects the next visible top-level entry after the current selection.
    /// Selects the first entry when nothing is currently selected. Doesn't scroll itself —
    /// `SheetRootView` syncs `focusedEntryId` to the new selection, and that focus activation
    /// is what triggers the scroll, in the row's own `onChange`.
    func selectNextEntry() {
        let entries = sheetModel.entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
        guard !entries.isEmpty else { return }
        guard let currentId = selectedEntryId,
              let currentIndex = entries.firstIndex(where: { $0.id == currentId }) else {
            if let first = entries.first { setSelected(first, parent: sheetModel) }
            return
        }
        let nextIndex = currentIndex + 1
        guard nextIndex < entries.count else { return }
        setSelected(entries[nextIndex], parent: sheetModel)
    }

    /// Selects the previous visible top-level entry before the current selection. Doesn't
    /// scroll itself — see `selectNextEntry`.
    func selectPreviousEntry() {
        let entries = sheetModel.entries.filter { !$0.isHidden && !$0.isGeneratedHidden }
        guard !entries.isEmpty,
              let currentId = selectedEntryId,
              let currentIndex = entries.firstIndex(where: { $0.id == currentId }),
              currentIndex > 0 else { return }
        setSelected(entries[currentIndex - 1], parent: sheetModel)
    }

    /// (parent, entry) pair for menu-bar/Commands consumers — see SelectedSheetEntry.
    /// Gated on `persistsEdits`, not just `isEditor`: a game view deliberately
    /// treated as an editor too (`isGameEditor`, e.g. CharacterRPG's) should
    /// get the same menu-bar/keyboard-shortcut editing commands.
    var selectedSheetEntryFocusValue: SelectedSheetEntry? {
        guard persistsEdits,
              let selectedParentModel,
              containsIdentity(selectedParentModel, in: sheetModel),
              let entry = selectedEntry else { return nil }
        return SelectedSheetEntry(rootModel: self, parentModel: selectedParentModel, entryModel: entry, isEditor: isEditor)
    }

    /// The currently selected entry itself, or nil if nothing (or only the root row) is selected.
    public var selectedEntry: SheetModel? {
        guard let selectedEntryId, selectedEntryId != sheetModel.id else { return nil }
        if let selectedEntryModel {
            return containsIdentity(selectedEntryModel, in: sheetModel) ? selectedEntryModel : nil
        }
        return findEntry(id: selectedEntryId, in: sheetModel)
    }

    private func containsIdentity(_ target: SheetModel, in model: SheetModel) -> Bool {
        identityPath(to: target, in: model) != nil
    }

    private func identityPath(to target: SheetModel, in model: SheetModel) -> [SheetModel]? {
        if model === target { return [model] }
        for entry in model.inlineEntries + model.entries {
            if let childPath = identityPath(to: target, in: entry) {
                return [model] + childPath
            }
        }
        return nil
    }
}
