// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
struct ListController {
    let modelContext: ModelContext
    let listModel: OldListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    enum ListType {
        case main
        case link
    }
    
    @MainActor static func listController(for type: ListType, modelContext: ModelContext, listModel: OldListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel) -> ListController {
        switch type {
        case .main:
            ListController(modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        case .link:
            ListController(modelContext: modelContext, listModel: OldListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        }
    }
}

extension ListController: OldListControllable {
    typealias Model = PhotoDataModel
}
