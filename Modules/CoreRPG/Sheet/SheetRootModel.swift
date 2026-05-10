// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModelId: Hashable {
    case item(UUID)
    case entry(UUID)
}

@MainActor @Observable
public final class SheetRootModel: Sendable {
    public init(linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool) {
        self.linkControllable = linkControllable
        self.isEditor = isEditor
        let sheetModel = sheetControllable.sheet(root: linkControllable.rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = sheetModel
        self.editorModel = SheetEditorModel(itemId: itemId, module: sheetModel.source.typeId)
        updateFilteredEntries()
    }

    public init(linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID, isEditor: Bool, editorModel: SheetEditorModel) {
        self.linkControllable = linkControllable
        self.isEditor = isEditor
        let sheetModel = sheetControllable.sheet(root: linkControllable.rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: isEditor)
        self.sheetModel = sheetModel
        self.editorModel = editorModel
        updateFilteredEntries()
    }
    
    let isEditor: Bool
    public let editorModel: SheetEditorModel
    private(set)var sheetModel: SheetModel
    var searchText: String = "" {
        didSet {
            let wasEmpty = oldValue.isEmpty
            let isEmpty = searchText.isEmpty
            
            // Save state when starting search
            if wasEmpty && !isEmpty {
                saveIsShownState(sheetModel: sheetModel)
            }
            
            updateFilteredEntries()
        }
    }
    
    @ObservationIgnored let linkControllable: any LinkControllable
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]
    
    func rootController(for module: NetworkModules) -> ItemRootController? {
        linkControllable.rootManager.itemRootController(for: module)
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
            }
        }
    }
    
    func toggleShown(sheetModel: SheetModel, entryId: UUID, linkId: UUID, module: NetworkModules) -> Bool {
        for entrySheetModel in sheetModel.entries {
            if entrySheetModel.id == entryId {
                if let existingSheet = entrySheetModel.entries.first(where: { $0.source.itemId == linkId }) {
                    unfold(sheetModel: existingSheet)
                    existingSheet.isShown.toggle()
                    return true
                } else {
                    // Link doesn't exist - add it using SheetController
                    if let rootModel = linkControllable.rootManager.rootModel(for: module) {
                        let newSheet = rootModel.sheetControllable.sheet(
                            root: linkControllable.rootManager,
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
        guard let sheetController = linkControllable.rootManager.rootModel(for: sheetModel.source.typeId)?.sheetControllable else { return }
        sheetController.unfold(root: linkControllable.rootManager, sheetModel: sheetModel)
    }
    
    // MARK: - Search
    
    private func saveIsShownState(sheetModel: SheetModel) {
        sheetModel.lastIsShown = sheetModel.isShown
        sheetModel.entries.forEach { saveIsShownState(sheetModel: $0) }
    }
    
    private func updateFilteredEntries() {
        _ = sheetModel.filter(searchText: searchText)
        linkTextModel.values.forEach {
            $0.reset(highlightedText: searchText)
        }
    }
    
    // MARK: - Editor
    
    func removeEntry(entryModel: SheetModel, from parentModel: SheetModel) {
        entryDataEditable(for: entryModel.source)?.removeEntry(source: entryModel.source)
        parentModel.entries.removeAll(where: { $0.id == entryModel.id })
        linkTextModel[.entry(entryModel.id)] = nil
        updateFilteredEntries()
    }

    /// Update the sheet model after inline edits
    func updateSheetModel(entryModel: SheetModel, updatedText: String) {
        guard let model = linkTextModel[.entry(entryModel.id)] else { return }
        entryModel.description = updatedText
        model.reset(text: entryModel.content)
    }
    
    func addNewEntry(in sheetModel: SheetModel) -> UUID? {
        guard let entryId = addNewEntry(to: sheetModel.source) else { return nil }
        //setCurrentItem(source: sheetModel.source, entryId: entryId)
        editorModel.itemId = sheetModel.source.itemId
        editorModel.module = sheetModel.source.typeId
        editorModel.entryId = entryId
        return entryId
    }
    
    func setScrollEntryId(source: ItemRowModel, entryId: UUID?) {
        guard let editController = editControllable(for: source) else { return }
        editController.editorModel.scrollEntryId = entryId
    }

    private func addNewEntry(to source: ItemRowModel) -> UUID? {
        guard let editable = entryDataEditable(for: source) else { return nil }
        return editable.addNewEntry(itemId: source.itemId)
    }

    func update(sheetModel: SheetModel, previousEntryId: UUID?, currentEntryId: UUID?) {
        guard let previousEntryId, currentEntryId == nil, editorModel.itemId == sheetModel.source.itemId else { return }

        updateParent(sheetModel)

        guard let entryModel = sheetModel.entries.first(where: { $0.source.entryId == previousEntryId }) else { return }
        entryModel.isEditing = false

        guard let model = linkTextModel[.entry(entryModel.id)] else { return }
        model.reset(text: entryModel.content)
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
              let index = parentModel.entries.firstIndex(where: { $0.id == entryModel.id }) else { return }
        let newIndex = up ? index - 1 : index + 2
        guard newIndex >= 0, newIndex <= parentModel.entries.count else { return }
        parentModel.entries.move(fromOffsets: IndexSet(integer: index), toOffset: newIndex)
        editable.move(itemId: parentModel.source.itemId, entryIds: parentModel.entries.compactMap { $0.source.entryId })
        updateFilteredEntries()
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

    /// Re-syncs a SheetModel tree from live data, then invalidates linkTextModel cache for any entry
    /// whose content changed (hasChanged) and clears the flag.
    func updateParent(_ parentModel: SheetModel) {
        rootController(for: parentModel.source.typeId)?.sheetControllable.update(root: linkControllable.rootManager, sheetModel: parentModel, isEditor: isEditor)
        resetChangedLinkModels(in: parentModel)
        if !searchText.isEmpty {
            updateFilteredEntries()
        }
    }

    private func resetChangedLinkModels(in sheetModel: SheetModel) {
        if sheetModel.hasChanged {
            linkTextModel[.item(sheetModel.id)] = nil
            linkTextModel[.entry(sheetModel.id)] = nil
            sheetModel.hasChanged = false
        }
        for entry in sheetModel.entries {
            if entry.hasChanged {
                linkTextModel[.entry(entry.id)] = nil
                entry.hasChanged = false
            }
            resetChangedLinkModels(in: entry)
        }
    }

}
