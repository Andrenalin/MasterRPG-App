// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
struct FakeListController: ListControllable {
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel    
}
