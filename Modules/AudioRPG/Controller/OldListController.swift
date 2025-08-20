// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
struct OldListController {
    let modelContext: ModelContext
    let listModel: OldListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    enum ListType {
        case main
        case link
    }
    
    @MainActor static func listController(for type: ListType, modelContext: ModelContext, listModel: OldListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel) -> OldListController {
        switch type {
        case .main:
            OldListController(modelContext: modelContext, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        case .link:
            OldListController(modelContext: modelContext, listModel: OldListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        }
    }
}

extension OldListController: OldListControllable {
    typealias Model = AudioDataModel
}
