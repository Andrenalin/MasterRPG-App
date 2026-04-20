// @copyright André Trettin

import SwiftUI

enum LinkHighlightTextModelId: Hashable {
    case name
    case description
    case item(String)
    case entry(String)
}

@MainActor @Observable
public final class SheetRootModel: Sendable {
    init(linkControllable: any LinkControllable, sheetControllable: SheetControllable, itemId: UUID) {
        self.linkControllable = linkControllable
        self.sheetModel = sheetControllable.sheet(root: linkControllable.rootManager, itemId: itemId, destination: nil, level: 0)
        
        updateFilteredEntries()
    }
    
    var sheetModel: SheetModel
    
    private(set) var filteredEntries: [SheetModel] = []
    var searchText: String = "" {
        didSet {
            updateFilteredEntries()
        }
    }

    
    @ObservationIgnored let linkControllable: any LinkControllable
    @ObservationIgnored private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]

    func rootController(for module: NetworkModules) -> ItemRootController? {
        linkControllable.rootManager.itemRootController(for: module)
    }

    
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
    
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        withAnimation {
            let rowModel = ItemRowModel(itemId: itemId, typeId: module)
            
            switch id {
            case .name:
                break
            case .description:
                break
            case .item(let uuid):
                break
//                let sheets = linkControllable.toggleSheet(itemId: itemId, entryId: entryId, level: 0, module: module)
//                sheetModel.entries.insert(contentsOf: sheets.entries, at: 0)
            case .entry(let uuid):
                break
//                guard let entryIndex = sheetModel.entries.firstIndex(where: { $0.id == uuid }) else { return }
//                var entry = sheetModel.entries[entryIndex]
//                if entry.sheetIds.contains(rowModel) {
//                    entry.sheetIds.removeAll(where: { $0 == rowModel })
//                } else {
//                    let model = linkControllable.itemControllable.itemOrEmpty(for: itemId)
//                    let TableFirstSheetModel = TableFirstSheetModel(linkControllable: linkControllable, parent: self, model: model, level: entry.level + 1, module: module, searchText: searchText, maxDepth: maxDepth)
//
//                    sheets[rowModel] = TableFirstSheetModel
//                    entry.sheetIds.append(rowModel)
//                }
//                sheetModel.entries[entryIndex] = entry
//                updateFilteredEntries()
            }
        }
    }
    
    // MARK: - Search
    
    private func updateFilteredEntries() {
        filteredEntries = sheetModel.filter(searchText: searchText)
    }

}
