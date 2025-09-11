// @copyright André Trettin

import SwiftUI

@Observable
public final class TableSheetModel {
    public init(linkController: LinkRootController, sheetModel: SheetModel, searchModel: SearchModel, editEnabled: Bool = false) {
        self.linkController = linkController
        self.sheetModel = sheetModel
        self.searchModel = searchModel
        id = UUID()
        self.editEnabled = editEnabled
    }
    var id: UUID
    var sheetModel: SheetModel
    var searchModel: SearchModel
    let editEnabled: Bool

    @ObservationIgnored
    var linkController: LinkRootController

    @ObservationIgnored
    var sheets: [UUID: TableSheetModel] = [:]
    
    @ObservationIgnored
    private var linkTextModel: [LinkHighlightTextModelId: LinkHighlightTextModel] = [:]

    @MainActor
    func description(for sheetModel: SheetModel) -> String? {
        guard !searchModel.searchText.isEmpty else { return sheetModel.description }
        return sheetModel.description.localizedCaseInsensitiveContains(searchModel.searchText) ? sheetModel.description : nil
    }
    
    @MainActor
    func linkTextModel(for id: LinkHighlightTextModelId, text: String) -> LinkHighlightTextModel {
        guard let model = linkTextModel[id] else {
            let editAction = editEnabled ? { link in self.editActions(for: id, linkModel: link) } : nil
            let model = LinkHighlightTextModel(linkController: linkController, text: text, highlightedText: searchModel.searchText, toggler: {
                self.toggle(id: id, itemId: $0, module: $1)
            }, editAction: editAction)
            
            linkTextModel[id] = model
            return model
        }
        return model
    }
    
    @MainActor
    func updateSearch() {
        linkTextModel.forEach {
            $0.value.reset(highlightedText: searchModel.searchText)
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
    func editActions(for id: LinkHighlightTextModelId, linkModel: LinkDataModel) -> Bool {
        toggle(id: id, itemId: linkModel.sourceId, module: linkModel.sourceModule, close: true)
        // remove from data
        return true
    }
    
    @MainActor
    func toggle(id: LinkHighlightTextModelId, itemId: UUID, module: NetworkModules, close: Bool = false) {
        switch id {
        case .description:
            let sheets = linkController.toggleSheet(itemId: itemId, level: 0, module: module)
            sheetModel.groups.insert(contentsOf: sheets?.groups ?? [], at: 0)
        case .group(let uuid):
            guard let groupIndex = sheetModel.groups.firstIndex(where: { $0.id == uuid }) else { return }
            var group = sheetModel.groups[groupIndex]
            if group.sheetIds.contains(itemId) {
                group.sheetIds.removeAll(where: { $0 == itemId })
            } else {
                guard let sheet = linkController.toggleSheet(itemId: itemId, level: group.level + 1, module: module) else { return }
                let tableSheetModel = TableSheetModel(linkController: linkController, sheetModel: sheet, searchModel: searchModel, editEnabled: editEnabled)
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
