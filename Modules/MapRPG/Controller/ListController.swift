// @copyright André Trettin

import CoreRPG
import Combine
import SwiftUI

struct ListController: Sendable {
    init(itemController: ItemController, itemListModel: ListModel) {
        self.itemController = itemController
        self.model = itemListModel
    }

    @MainActor
    init(itemController: ItemController, listStoreName: LocalizedStringResource, hasChildren: Bool, searchToken: ItemListCategory, categoryTags: [ItemListCategory], selectedItems: [ItemRowTreeModel] = []) {
        self.itemController = itemController
        self.model = ListModel(searchToken: searchToken, categoryTags: [ItemListCategory.all] + categoryTags, listStoreName: String(localized: listStoreName).localizedString, hasChildren: hasChildren)
    }

    let itemController: ItemController
    let model: ListModel
}

extension ListController: ListControllable {
    var itemControllable: any ItemControllable {
        itemController as ItemController
    }
}
