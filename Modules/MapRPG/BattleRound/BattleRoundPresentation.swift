// @copyright André Trettin

import Foundation

enum BattleRoundPresentation: Identifiable {
    case sheet(BattleCharacterSheetPresentation)
    case selection(UUID)

    var id: UUID {
        switch self {
        case .sheet(let sheet): sheet.id
        case .selection(let combatantId): combatantId
        }
    }
}
