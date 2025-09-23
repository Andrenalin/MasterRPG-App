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
        DiceRoute.detail(itemId)
    }
}
