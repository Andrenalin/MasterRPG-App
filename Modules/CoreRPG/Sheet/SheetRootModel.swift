// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModelId: Hashable {
    case item(UUID)
    case entry(UUID)
    case entryContent(UUID)
}

@MainActor @Observable
public final class SheetRootModel: Sendable {
    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        let sheetModel = sheetControllable.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: itemId, module: sheetModel.source.typeId)
        // Initialize lastIsShown to match isShown so first search clear works correctly
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool, editorModel: SheetEditorModel) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        let sheetModel = sheetControllable.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = sheetModel
        self.editorModel = editorModel
        // Initialize lastIsShown to match isShown so first search clear works correctly
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    // Use this init in fake/testing contexts where a real SheetModel tree is already built.
    // FakeSheetController.sheet ignores the root parameter anyway, so passing
    // the SheetModel directly avoids needing a real cross-module sheet() call.
    public init(rootManager: RootManager, linkControllable: any LinkControllable, sheetControllable: SheetControllable, sheetModel: SheetModel, isEditor: Bool) {
        self.rootManager = rootManager
        self.linkControllable = linkControllable
        self.sheetControllable = sheetControllable
        self.isEditor = isEditor
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: sheetModel.source.itemId, module: sheetModel.source.typeId)
        initializeLastIsShownState(sheetModel: sheetModel)
    }

    let isEditor: Bool
    public let editorModel: SheetEditorModel
    public private(set)var sheetModel: SheetModel
    private var hasActiveSearch: Bool = false

    public var searchText: String = "" {
        didSet {
            let wasEmpty = oldValue.isEmpty
            let isEmpty = searchText.isEmpty

            // Save state when starting search (before filter modifies anything)
            if wasEmpty && !isEmpty {
                saveIsShownState(sheetModel: sheetModel)
                hasActiveSearch = true
            }

            // Determine if we should restore state (when clearing an active search)
            let shouldRestore = !wasEmpty && isEmpty && hasActiveSearch

            // Clear search flag when search is cleared
            if !wasEmpty && isEmpty {
                hasActiveSearch = false
            }

            updateFilteredEntries(shouldRestoreState: shouldRestore)
        }
    }
    
    @ObservationIgnored let rootManager: RootManager
    @ObservationIgnored let sheetControllable: SheetControllable
    @ObservationIgnored let linkControllable: any LinkControllable
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]
    
    /// Reset this model for a new item without replacing the instance.
    /// Callers in other modules (e.g. DetailEditorView in each RPG module) use this
    /// to avoid a @State assignment, which would otherwise re-run DetailEditorView.body
    /// and recreate SheetRootEditorView with a new sheetRootModel reference — causing
    /// SheetRootEditorView to see "@self changed" whenever the async task completed
    /// (which the user perceived as an update "while scrolling").
    public func reset(itemId: UUID) {
        guard sheetModel.source.itemId != itemId else { return }
        // Load the sheet model for the new item first so any search filter
        // that runs afterward operates on the correct data.
        let newSheetModel = sheetControllable.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = newSheetModel
        self.editorModel.setEdit(source: newSheetModel.source)
        // Clear stale per-item caches so new views build fresh link text models.
        linkTextModel = [:]
        // Clear search state without restoring saved visibility (hasActiveSearch=false
        // means didSet will not attempt a restore when searchText is set to "").
        hasActiveSearch = false
        searchText = ""
    }
    
    func rootController(for module: NetworkModules) -> ItemRootController? {
        rootManager.itemRootController(for: module)
    }

    var linkRootController: LinkControllable? {
        rootController(for: .adventure)?.linkControllable
    }
        
    /// Get the correct EditControllable for a source (handles cross-module)
    func editControllable(for source: ItemRowModel) -> (any EditControllable)? {
        rootController(for: source.typeId)?.editControllable
    }

    /// Get the correct EntryDataEditable for a source (handles cross-module)
    func entryDataEditable(for source: ItemRowModel) -> (any EntryDataEditable)? {
        editControllable(for: source) as? (any EntryDataEditable)
    }
    
    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }
    
    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkRootController, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        withAnimation {
            switch id {
            case .item:
                break
            case .entry(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module)
            case .entryContent(let uuid):
                _ = toggleShown(sheetModel: sheetModel, entryId: uuid, linkId: itemId, module: module)
            }
        }
    }
    
    func toggleShown(sheetModel: SheetModel, entryId: UUID, linkId: UUID, module: NetworkModules) -> Bool {
        for entrySheetModel in sheetModel.entries {
            // Compare entryId (UUID) with source.entryId or source.itemId
            let matchesEntry = entrySheetModel.source.entryId == entryId || entrySheetModel.source.itemId == entryId
            if matchesEntry {
                if let existingSheet = entrySheetModel.entries.first(where: { $0.source.itemId == linkId }) {
                    unfold(sheetModel: existingSheet)
                    existingSheet.isShown.toggle()
                    return true
                } else {
                    // Link doesn't exist - add it using SheetController
                    if let rootModel = rootManager.rootModel(for: module) {
                        let newSheet = rootModel.sheetControllable.sheet(
                            root: rootManager,
                            itemId: linkId,
                            destination: entrySheetModel.destination,
                            level: entrySheetModel.level + 1,
                            isShown: true,
                            moduleDepth: 0,
                            isEditor: isEditor
                        )
                        unfold(sheetModel: newSheet)
                        entrySheetModel.entries.append(newSheet)
                        return true
                    }
                }
                return true
            }
            if toggleShown(sheetModel: entrySheetModel, entryId: entryId, linkId: linkId, module: module) {
                return true
            }
        }
        return false
    }
    
    func unfold(sheetModel: SheetModel) {
        guard let sheetController = rootManager.rootModel(for: sheetModel.source.typeId)?.sheetControllable else { return }
        sheetController.unfold(root: rootManager, sheetModel: sheetModel)
    }
    
    // MARK: - Search

    private func initializeLastIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { initializeLastIsShownState(sheetModel: $0) }
    }

    private func saveIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { saveIsShownState(sheetModel: $0) }
    }
    
    private func updateFilteredEntries(shouldRestoreState: Bool = false) {
        _ = sheetModel.filter(searchText: searchText, shouldRestoreState: shouldRestoreState)
        linkTextModel.values.forEach {
            $0.reset(highlightedText: searchText)
        }
    }
    
    // MARK: - Editor
    
    func removeEntry(entryModel: SheetModel, from parentModel: SheetModel) {
        entryDataEditable(for: entryModel.source)?.removeEntry(source: entryModel.source)
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
    }

    /// Update the sheet model after inline edits
    func updateSheetModel(entryModel: SheetModel, updatedText: String) {
        entryModel.description = updatedText
        let lookupId = entryModel.source.entryId ?? entryModel.source.itemId
        linkTextModel[.entry(lookupId)]?.reset(text: entryModel.name)
        linkTextModel[.entryContent(lookupId)]?.reset(text: entryModel.description)
    }
    
    func addNewEntry(in sheetModel: SheetModel) -> UUID? {
        guard let entryId = addNewEntry(to: sheetModel.source) else { return nil }
        //setCurrentItem(source: sheetModel.source, entryId: entryId)
        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }

    @MainActor func addNewGroup(in sheetModel: SheetModel) async -> UUID? {
        guard let editable = entryDataEditable(for: sheetModel.source) else { return nil }
        let entryId = await editable.addNewGroup(itemId: sheetModel.source.itemId)
        
        //setCurrentItem(source: sheetModel.source, entryId: entryId)
        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }

    func setScrollEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.sheetEditorModel.scrollEntryId = entryId
    }

    private func addNewEntry(to source: ItemRowModel) -> UUID? {
        guard let editable = entryDataEditable(for: source) else { return nil }
        return editable.addNewEntry(itemId: source.itemId)
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

    // MARK: - Context menu actions

    func duplicateEntry(entryModel: SheetModel, in parentModel: SheetModel) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source),
              let newId = editable.copy(itemId: entryModel.source.itemId, entryId: entryId) else { return }
        editorModel.setEdit(source: ItemRowModel(itemId: entryModel.source.itemId, entryId: newId, typeId: entryModel.source.typeId))
        updateParent(parentModel)
    }

    func moveEntry(entryModel: SheetModel, in parentModel: SheetModel, up: Bool) {
        guard let editable = entryDataEditable(for: entryModel.source),
              let index = parentModel.entries.firstIndex(where: { entry in
                  entry.source.itemId == entryModel.source.itemId &&
                  entry.source.entryId == entryModel.source.entryId
              }) else { return }
        let newIndex = up ? index - 1 : index + 2
        guard newIndex >= 0, newIndex <= parentModel.entries.count else { return }
        parentModel.entries.move(fromOffsets: IndexSet(integer: index), toOffset: newIndex)
        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId })
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    func reorderEntry(from sourceIndex: Int, to targetIndex: Int, in parentModel: SheetModel) {
        guard sourceIndex != targetIndex,
              let editable = entryDataEditable(for: parentModel.source),
              sourceIndex >= 0,
              sourceIndex < parentModel.entries.count,
              targetIndex >= 0,
              targetIndex < parentModel.entries.count else { return }

        let entry = parentModel.entries[sourceIndex]
        parentModel.entries.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex : targetIndex
        parentModel.entries.insert(entry, at: insertIndex)

        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId })
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    func moveEntry(fromItemId: UUID, entryId: UUID, toItemId: UUID, afterEntry: SheetModel) {
        guard let sourceEditable = entryDataEditable(for: ItemRowModel(itemId: fromItemId, typeId: afterEntry.source.typeId)) else { return }

        // Move the entry from source item to target item
        let success = sourceEditable.move(itemId: fromItemId, entryId: entryId, into: ItemRowModel(itemId: toItemId, typeId: afterEntry.source.typeId))

        guard success else { return }

        // Update the sheet models to reflect the changes
        updateFromRoot()
    }

    func handleDrop<LinkType: LinkDataTransferable>(items: [LinkType], targetEntry: SheetModel, parentModel: SheetModel) -> Bool {
        guard let droppedItem = items.first else { return false }

        if droppedItem.isMove {
            // ===== MOVE: Entry being moved (within same item or across items in same module) =====

            // Only allow moves within same module
            guard droppedItem.module == targetEntry.source.typeId else {
                return false
            }

            // Don't allow dropping on inline entries (like dice, photo, etc.)
            guard targetEntry.sheetType == .item || targetEntry.sheetType == .group else {
                return false
            }

            guard let draggedEntryId = droppedItem.entryId else {
                return false
            }

            // Check if this is a move within the same parent item (reorder)
            if droppedItem.itemId == parentModel.source.itemId,
               let draggedIndex = parentModel.entries.firstIndex(where: { $0.source.entryId == draggedEntryId }),
               let targetIndex = parentModel.entries.firstIndex(where: { entry in
                   entry.source.itemId == targetEntry.source.itemId &&
                   entry.source.entryId == targetEntry.source.entryId
               }),
               draggedIndex != targetIndex {
                // Reorder within same parent
                withAnimation {
                    reorderEntry(from: draggedIndex, to: targetIndex, in: parentModel)
                }
                return true
            }

            // Otherwise, move entry from one item to another (cross-item move)
            if droppedItem.itemId != targetEntry.source.itemId {
                withAnimation {
                    moveEntry(
                        fromItemId: droppedItem.itemId,
                        entryId: draggedEntryId,
                        toItemId: targetEntry.source.itemId,
                        afterEntry: targetEntry
                    )
                }
                return true
            }

            return false

        } else {
            // ===== LINK DROP: From inspector or viewer mode =====

            // Only allow link drops on item entries (not groups, not inline entries)
            guard targetEntry.sheetType == .item else {
                return false
            }

            items.forEach {
                addLink(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, to: targetEntry, in: parentModel)
            }
            return true
        }
    }

    func groupFolders(for entryModel: SheetModel) -> [FolderRepresentable] {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return [] }
        return editable.groupFolders(itemId: entryModel.source.itemId, sourceEntryId: entryId)
    }

    func moveEntry(_ entryModel: SheetModel, in parentModel: SheetModel, into folder: FolderRepresentable) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return }
        editable.move(itemId: entryModel.source.itemId, sourceEntryId: entryId, into: folder)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent(parentModel)
        }
    }

    func parentGroup(for entryModel: SheetModel) -> FolderRepresentable? {
        entryDataEditable(for: entryModel.source)?.parentFolder(itemId: entryModel.source.itemId)
    }

    func moveEntryOutOfGroup(_ entryModel: SheetModel, in parentModel: SheetModel, parent: FolderRepresentable) {
        guard let entryId = entryModel.source.entryId,
              let editable = entryDataEditable(for: entryModel.source) else { return }
        editable.moveOutOfGroup(itemId: entryModel.source.itemId, sourceEntryId: entryId, parent: parent)
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent(parentModel)
        }
    }

    func addLink(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, to destination: SheetModel, in parentModel: SheetModel) {
        guard let editable = entryDataEditable(for: destination.source),
              let destinationEntryId = destination.source.entryId else { return }
        editable.add(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destination.source.itemId, destinationEntryId: destinationEntryId)
        updateParent(parentModel)
    }

    func updateParent() {
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
    }

    /// Updates from the root SheetModel down - use when changes may affect calculated values throughout the tree
    func updateFromRoot() {
        rootController(for: sheetModel.source.typeId)?.sheetControllable.update(root: rootManager, sheetModel: sheetModel, isEditor: isEditor)
        resetChangedLinkModels(in: sheetModel)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    private func resetChangedLinkModels(in sheetModel: SheetModel) {
        if sheetModel.hasChanged {
            let lookupId = sheetModel.source.entryId ?? sheetModel.source.itemId
            linkTextModel[.item(sheetModel.source.itemId)]?.reset(text: sheetModel.name)
            linkTextModel[.entry(lookupId)]?.reset(text: sheetModel.description)
            linkTextModel[.entryContent(lookupId)]?.reset(text: sheetModel.description)
            sheetModel.hasChanged = false
        }
        for entry in sheetModel.entries {
            if entry.hasChanged {
                let lookupId = entry.source.entryId ?? entry.source.itemId
                linkTextModel[.entry(lookupId)]?.reset(text: entry.name)
                linkTextModel[.entryContent(lookupId)]?.reset(text: entry.description)
                entry.hasChanged = false
            }
            for subEntry in entry.entries {
                resetChangedLinkModels(in: subEntry)
            }
        }
    }
}
