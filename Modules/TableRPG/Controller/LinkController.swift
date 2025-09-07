// @copyright André Trettin

import CoreRPG
import Foundation

struct LinkController: LinkControllable {
    func toggleSheet(itemId: UUID, level: Int, module: CoreRPG.NetworkModules) -> CoreRPG.SheetModel? {
        nil
    }
    
    func collectLinks(of module: CoreRPG.NetworkModules, from itemId: UUID) -> [UUID] {
        []
    }
}
