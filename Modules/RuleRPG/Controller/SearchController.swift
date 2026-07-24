// @copyright André Trettin

import CoreRPG

struct SearchController: Sendable {
    let itemController: ItemController
}

extension SearchController: SearchControllable {
    var itemControllable: any ItemControllable { itemController }
}

