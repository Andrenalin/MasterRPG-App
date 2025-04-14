// @copyright André Trettin

import SwiftUI

@Observable
final class TableSheetModel {
    init(linkControllable: any LinkControllable, sheetModel: SheetModel, searchText: String = "") {
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
    var sheets: [UUID: TableSheetModel] = [:]
    
    @ObservationIgnored
    private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]

    func description(for sheetModel: SheetModel) -> String? {
        guard !searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchText) ? sheetModel.description : nil
    }
    
    @MainActor
    func linkTextModel(for id: LinkHighlightTextModelId, text: String) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let model = LinkHighlightTextModel(linkControllable: linkControllable, text: text, highlightedText: searchText) {
                self.toggle(id: id, itemId: $0, module: $1)
            }
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

    func group(groupId: UUID) -> SheetGroupModel? {
        sheetModel.groups.first { $0.id == groupId }
    }
    
    @MainActor
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules) {
        switch id {
        case .description:
            let sheets = linkControllable.toggleSheet(itemId: itemId, level: 0, module: module)
            sheetModel.groups.insert(contentsOf: sheets?.groups ?? [], at: 0)
        case .group(let uuid):
            guard let groupIndex = sheetModel.groups.firstIndex(where: { $0.id == uuid }) else { return }
            var group = sheetModel.groups[groupIndex]
            if group.sheetIds.contains(itemId) {
                group.sheetIds.removeAll(where: { $0 == itemId })
            } else {
                guard let sheet = linkControllable.toggleSheet(itemId: itemId, level: group.level + 1, module: module) else { return }
                let tableSheetModel = TableSheetModel(linkControllable: linkControllable, sheetModel: sheet, searchText: searchText)
                tableSheetModel.id = itemId
                sheets[tableSheetModel.id] = tableSheetModel
                group.sheetIds.append(tableSheetModel.id)
            }
            sheetModel.groups[groupIndex] = group
        case .entry(let uuid):
            //let group = sheetModel.groups.first(where: { $0.id == uuid })
            //level = 0
            break
        }        
    }
}

enum LinkHighlightTextModelId: Hashable {
    case description
    case group(UUID)
    case entry(UUID)
}
