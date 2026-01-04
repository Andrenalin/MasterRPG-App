// @copyright André Trettin

import SwiftUI

@Observable
public final class TableSheetModel {
    @MainActor public init(linkControllable: any LinkControllable, model: any ItemDataAccessable, level: Int, module: NetworkModules, searchText: String = "") {
        self.linkControllable = linkControllable
        self.model = model
        self.itemId = model.id
        self.level = level
        self.module = module
        self.sheetModel = linkControllable.toggleSheet(itemId: itemId, level: level, module: module)
        self.searchText = searchText
        id = model.id
    }
    
    let model: any ItemDataAccessable
    let id: UUID
    let itemId: UUID
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
        resetModel(model: linkControllable.toggleSheet(itemId: itemId, level: level, module: module))
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
                let sheets = linkControllable.toggleSheet(itemId: itemId, level: 0, module: module)
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
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, level: level, module: module)
        if let entryIndex = updatedModel.entries.firstIndex(where: { $0.source.entryId == entryId }) {
            let entry = updatedModel.entries[entryIndex]
            if entryIndex < sheetModel.entries.count {
                sheetModel.entries.insert(entry, at: entryIndex)
            } else {
                sheetModel.entries.append(entry)
            }
        }
    }

    @MainActor func update(entryId: UUID) {
        let updatedModel = linkControllable.toggleSheet(itemId: itemId, level: level, module: module)
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
}

enum LinkHighlightTextModelId: Hashable {
    case name
    case description
    case entry(String)
}
