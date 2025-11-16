// @copyright André Trettin

import AndrenalinKit
import Foundation

public struct LinkController: Sendable {
    init(itemController: ItemController, gameController: GameController) {
        self.itemController = itemController
        self.gameController = gameController
    }
    let itemController: ItemController
    let gameController: GameController
    
    public var itemControllable: any ItemControllable {
        itemController
    }
}

extension LinkController: LinkControllable {
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: AndrenalinKit.ShareValueResult?, toggler: ((UUID, AndrenalinKit.NetworkModules) async -> Void)?, editAction: ((AndrenalinKit.ItemRowModel) -> Bool)?) -> String {
        text
    }
}
