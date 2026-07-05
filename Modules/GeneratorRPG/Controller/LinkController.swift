// @copyright André Trettin

import CoreRPG
import Foundation

struct LinkController: Sendable {
    let itemController: ItemController

    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        text
    }
}
