// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class TableSheetModel: Sendable {
    public init(linkControllable: any LinkControllable, parent: TableSheetModel?, model: any ItemDataAccessable, entryId: UUID? = nil, level: Int, module: NetworkModules, searchText: String = "") {
        self.linkControllable = linkControllable
        self.parent = parent
        self.model = model
        self.itemId = model.id
        self.entryId = entryId
        self.level = level
        self.module = module
        self.sheetModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        self.searchText = searchText
        id = model.id
    }
    
    @ObservationIgnored let linkControllable: any LinkControllable
    let parent: TableSheetModel?
    let model: any ItemDataAccessable
    let id: UUID
    let itemId: UUID
    let entryId: UUID?
    let level: Int
    let module: NetworkModules
    
    var sheetModel: SheetModel
    var searchText: String = ""

    @ObservationIgnored var sheets: [ItemRowModel: TableSheetModel] = [:]
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]

    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }
    
    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkControllable, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    func updateSearch() {
        linkTextModel.forEach {
            $0.value.reset(highlightedText: searchText)
        }
        sheets.forEach {
            $0.value.updateSearch()
        }
    }
    
    func reset() {
        resetModel(model: linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module))
    }
    
    func resetModel(model: SheetModel) {
        linkTextModel.removeAll()
        sheets.removeAll()
        sheetModel = model
    }

    func entry(entryId: String) -> SheetModel? {
        sheetModel.entries.first { $0.id == entryId }
    }

    func hasEntry(entryId: UUID) -> Bool {
        sheetModel.entries.first { $0.source.entryId == entryId } != nil 
    }

    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        withAnimation {
            let rowModel = ItemRowModel(itemId: itemId, typeId: module)
            
            switch id {
            case .name:
                break
            case .description:
                let sheets = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: 0, module: module)
                sheetModel.entries.insert(contentsOf: sheets.entries, at: 0)
            case .entry(let uuid):
                guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == uuid }) else { return }
                var entry = sheetModel.entries[entryIndex]
                if entry.sheetIds.contains(rowModel) {
                    entry.sheetIds.removeAll(where: { $0 == rowModel })
                } else {
                    let model = linkControllable.itemControllable.itemOrEmpty(for: itemId)
                    let tableSheetModel = TableSheetModel(linkControllable: linkControllable, parent: self, model: model, level: entry.level + 1, module: module, searchText: searchText)
                    
                    sheets[rowModel] = tableSheetModel
                    entry.sheetIds.append(rowModel)
                }
                sheetModel.entries[entryIndex] = entry
            }
        }
    }

    func add(entryId: UUID) {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        if let entryIndex = updatedModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            let entry = updatedModel.entries[entryIndex]
            if entryIndex < sheetModel.entries.count {
                sheetModel.entries.insert(entry, at: entryIndex)
            } else {
                sheetModel.entries.append(entry)
            }
        }
    }
    
    func subTableModel(source: ItemRowModel) -> TableSheetModel? {
        if let subModel = sheets[source] {
            return subModel
        }
        for subModel in sheets.values {
            if let model = subModel.subTableModel(source: source) {
                return model
            }
        }
        return nil
    }

    func move(itemId: UUID, entryId: UUID, into source: ItemRowModel) {
        let otherSource = ItemRowModel(itemId: itemId, entryId: nil, typeId: source.typeId)
        if let subSheetModel = subTableModel(source: otherSource) {
            if let entry = subSheetModel.sheetModel.entries.first(where: { $0.source.entryId == entryId }) {
                subSheetModel.remove(entry: entry)
            }
        }
        add(entryId: entryId)
    }

    func move(itemId: UUID, indexSet: IndexSet, to: Int) {
        sheetModel.entries.move(fromOffsets: indexSet, toOffset: to)
    }

    func move(entryDataEditable: (any EntryDataEditable)?, indexSet: IndexSet, to index: Int) {
        guard let entryDataEditable else { return }
        move(itemId: sheetModel.source.itemId, indexSet: indexSet, to: index)
        entryDataEditable.move(itemId: sheetModel.source.itemId, entryIds: sheetModel.entries.compactMap { $0.source.entryId })
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            updateParent()
        }
    }
    
    func update(entryId: UUID) {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        if let entryIndex = updatedModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            let entry = updatedModel.entries[entryIndex]
            if entryIndex < sheetModel.entries.count {
                sheetModel.entries[entryIndex] = entry
                linkTextModel[.entry(entry.id)] = nil
            }
        } else if updatedModel.source.entryId == entryId, let entryIndex = sheetModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            var updatedEntry = sheetModel.entries[entryIndex]
            if updatedEntry.description != updatedModel.description || updatedEntry.name != updatedModel.name {
                updatedEntry.description = updatedModel.description
                updatedEntry.name = updatedModel.name
                sheetModel.entries[entryIndex] = updatedEntry
                linkTextModel[.entry(updatedEntry.id)] = nil
            }
        }
    }
    
    func updateParent() {
        guard parent == nil else {
            parent?.updateParent()
            return
        }
        updateModels()
    }
    
    func updateModels() {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        let entries = updatedModel.entries.map {
            var entry = $0
            guard let localIndex = sheetModel.entries.firstIndex(where: { $0.source == entry.source }) else { return entry }
            let localEntry = sheetModel.entries[localIndex]
            if entry.name != localEntry.name || entry.description != localEntry.description {
                linkTextModel[.entry(entry.id)] = nil
            }
            entry.sheetIds = localEntry.sheetIds
            return entry
        }
        sheetModel.entries <=> entries
        sheets.values.forEach {
            $0.updateModels()
        }
    }

    func remove(entry: SheetModel) {
        sheetModel.entries.removeAll(where: { $0.id == entry.id })
        linkTextModel[.entry(entry.id)] = nil
    }
    
    // Quick Editor
    func toggleEdit(entry: SheetModel) {
        guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        let rowModel = ItemRowModel(itemId: itemId, typeId: module)
        if entry.sheetIds.contains(rowModel) {
            entry.sheetIds.removeAll(where: { $0 == rowModel })
        } else {
            let model = linkControllable.itemControllable.itemOrEmpty(for: itemId)
            let tableSheetModel = TableSheetModel(linkControllable: linkControllable, parent: self, model: model, entryId: entry.source.entryId, level: entry.level + 1, module: module, searchText: searchText)
            
            sheets[rowModel] = tableSheetModel
            entry.sheetIds.append(rowModel)
        }
        sheetModel.entries[entryIndex] = entry
    }
    
    func isEditing(entry: SheetModel) -> Bool {
        entry.sheetIds.contains(ItemRowModel(itemId: itemId, typeId: module))
    }
}

enum LinkHighlightTextModelId: Hashable {
    case name
    case description
    case entry(String)
}
