// @copyright André Trettin

import CoreRPG
import Foundation

struct BattleCharacterSheetPresentation: Identifiable {
    let id: UUID
    let name: String
    let root: ItemRootController
    let sheet: SheetRootModel
}
