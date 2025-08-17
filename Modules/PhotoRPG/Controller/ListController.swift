// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ListController {
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    enum ListType {
        case main
        case link
    }
    
    @MainActor static func listController(for type: ListType, listModel: ListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel) -> ListController {
        switch type {
        case .main:
            ListController(listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        case .link:
            ListController(listModel: ListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        }
    }
}

extension ListController: ListControllable {
    typealias Model = PhotoDataModel
}
