// @copyright André Trettin

import CoreRPG
import Foundation

extension TableModel {
    /// The editor window's forced save during a game: the table type and dice it changed reach
    /// the library too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: TableModel, to edited: TableModel) {
        if base.tableType != edited.tableType { tableType = edited.tableType }
        if base.diceId != edited.diceId { diceId = edited.diceId }
    }
}
