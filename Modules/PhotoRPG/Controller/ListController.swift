// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
struct ListController {
    let modelContext: ModelContext
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    enum ListType {
        case main
        case link
    }
    
    @MainActor static func listController(for type: ListType, modelContext: ModelContext, listModel: ListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel) -> ListController {
        switch type {
        case .main:
            ListController(modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        case .link:
            ListController(modelContext: modelContext, listModel: ListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        }
    }
}

extension ListController: ListControllable {
    typealias Model = PhotoDataModel
}
