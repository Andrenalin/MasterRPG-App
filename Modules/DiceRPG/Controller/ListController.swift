// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
struct ListController: ListControllable {
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
}
