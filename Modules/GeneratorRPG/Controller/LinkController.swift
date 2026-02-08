// @copyright André Trettin

import CoreRPG
import Foundation

struct LinkController: Sendable {
    let rootManager: RootManager
    let itemController: ItemController
    let gameController: GameController
    
    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }
}
