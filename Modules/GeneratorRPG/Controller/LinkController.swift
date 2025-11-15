// @copyright André Trettin

import AndrenalinKit
import Foundation

struct LinkController: Sendable {
    var module: NetworkModules
    var itemController: ItemController
    
    var itemControllable: any ItemControllable {
        itemController
    }
}

extension LinkController: LinkControllable {}
