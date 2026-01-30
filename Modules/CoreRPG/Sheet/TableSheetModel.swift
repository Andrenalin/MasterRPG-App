// @copyright André Trettin

import SwiftUI

@Observable
public final class TableSheetModel {
    @MainActor public init(linkControllable: any LinkControllable, model: any ItemDataAccessable, entryId: UUID? = nil, level: Int, module: NetworkModules, searchText: String = "") {
        self.linkControllable = linkControllable
        self.model = model
        self.itemId = model.id
        self.entryId = entryId
        self.level = level
        self.module = module
        self.sheetModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        self.searchText = searchText
        id = model.id
    }
    
    let model: any ItemDataAccessable
    let id: UUID
    let itemId: UUID
    let entryId: UUID?
    let level: Int
    let module: NetworkModules
    
    var sheetModel: SheetModel
    var searchText: String = ""

    @ObservationIgnored
    var linkControllable: any LinkControllable

    @ObservationIgnored
    var sheets: [ItemRowModel: TableSheetModel] = [:]
    
    @ObservationIgnored
    private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]

    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }
    
    @MainActor
    func linkTextModel(for id: LinkHighlightTextModelId, text: String, shareResults: ShareValueResult? = nil) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkControllable, text: text, highlightedText: searchText, toggler: { self.toggle(id: id, itemId: $0, module: $1) }, shareResult: shareResults)
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    @MainActor
    func updateSearch() {
        linkTextModel.forEach {
            $0.value.reset(highlightedText: searchText)
        }
        sheets.forEach {
            $0.value.updateSearch()
        }
    }
    
    @MainActor func reset() {
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
    
    @MainActor
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
                    let tableSheetModel = TableSheetModel(linkControllable: linkControllable, model: model, level: entry.level + 1, module: module, searchText: searchText)
                    
                    sheets[rowModel] = tableSheetModel
                    entry.sheetIds.append(rowModel)
                }
                sheetModel.entries[entryIndex] = entry
            }
        }
    }

    @MainActor func add(entryId: UUID) {
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
    
    @MainActor func subTableModel(source: ItemRowModel) -> TableSheetModel? {
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

    @MainActor func move(itemId: UUID, entryId: UUID, into source: ItemRowModel) {
        let otherSource = ItemRowModel(itemId: itemId, entryId: nil, typeId: source.typeId)
        if let subSheetModel = subTableModel(source: otherSource) {
            if let entry = subSheetModel.sheetModel.entries.first(where: { $0.source.entryId == entryId }) {
                subSheetModel.remove(entry: entry)
            }
        }
        add(entryId: entryId)
    }

    @MainActor func move(itemId: UUID, indexSet: IndexSet, to: Int) {
        sheetModel.entries.move(fromOffsets: indexSet, toOffset: to)
    }

    @MainActor func update(entryId: UUID) {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: level, module: module)
        if let entryIndex = updatedModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            let entry = updatedModel.entries[entryIndex]
            if entryIndex < sheetModel.entries.count {
                sheetModel.entries[entryIndex] = entry
                linkTextModel[.entry(entry.id)] = nil
            }
        }
    }

    func remove(entry: SheetModel) {
        sheetModel.entries.removeAll(where: { $0.id == entry.id })
        linkTextModel[.entry(entry.id)] = nil
    }
    
    // Quick Editor
    @MainActor func toggleEdit(entry: SheetModel) {
        guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        let rowModel = ItemRowModel(itemId: itemId, typeId: module)
        if entry.sheetIds.contains(rowModel) {
            entry.sheetIds.removeAll(where: { $0 == rowModel })
        } else {
            let model = linkControllable.itemControllable.itemOrEmpty(for: itemId)
            let tableSheetModel = TableSheetModel(linkControllable: linkControllable, model: model, entryId: entry.source.entryId, level: entry.level + 1, module: module, searchText: searchText)
            
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
