// @copyright André Trettin

import SwiftUI

struct FakeListController: ListControllable {
    init(itemControllable: any ItemControllable, model: ListModel) {
        self.itemControllable = itemControllable
        self.model = model
    }
    
    var itemControllable: any ItemControllable
    var model: ListModel
    
    
    @MainActor
    static let fake = FakeListController(itemControllable: FakeItemController.fake, model: ListModel(searchToken: .all, categoryTags: [], listStoreName: "Test", hasChildren: false))
}
