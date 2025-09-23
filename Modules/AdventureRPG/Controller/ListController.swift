// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftData
import SwiftUI

@MainActor
struct ListController: ListControllable {
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    func detailDestination(for itemId: UUID) -> any NavigationDestination {
        AdventureRoute.detail(itemId)
    }

    enum ListType {
        case main
        case link
    }
    
    @MainActor static func listController(for type: ListType, listDisplayModel: ListDisplayModel, searchModel: SearchModel) -> ListController {
        switch type {
        case .main:
            ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        case .link:
            ListController(listModel: ListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        }
    }
}
