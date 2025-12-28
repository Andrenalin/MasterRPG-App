// @copyright André Trettin

import SwiftUI

@Observable
public final class TableSheetModel {
    public init(linkControllable: any LinkControllable, sheetModel: SheetModel, searchText: String = "") {
        self.linkControllable = linkControllable
        self.sheetModel = sheetModel
        self.searchText = searchText
        id = UUID()
    }
    var id: UUID
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
                sheetModel.entries.insert(contentsOf: sheets?.entries ?? [], at: 0)
            case .entry(let uuid):
                guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == uuid }) else { return }
                var entry = sheetModel.entries[entryIndex]
                if entry.sheetIds.contains(rowModel) {
                    entry.sheetIds.removeAll(where: { $0 == rowModel })
                } else {
                    guard let sheet = linkControllable.toggleSheet(itemId: itemId, level: entry.level + 1, module: module) else { return }
                    let tableSheetModel = TableSheetModel(linkControllable: linkControllable, sheetModel: sheet, searchText: searchText)
                    tableSheetModel.id = itemId
                    
                    sheets[rowModel] = tableSheetModel
                    entry.sheetIds.append(rowModel)
                }
                sheetModel.entries[entryIndex] = entry
            }
        }
    }
}

enum LinkHighlightTextModelId: Hashable {
    case name
    case description
    case entry(String)
}
