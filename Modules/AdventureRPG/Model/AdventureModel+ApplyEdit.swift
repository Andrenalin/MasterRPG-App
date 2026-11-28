// @copyright André Trettin

import CoreRPG
import Foundation

extension AdventureModel {
    /// The editor window's forced save during a game: the dice, photo, group and table players
    /// it changed reach the library too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: AdventureModel, to edited: AdventureModel) {
        if base.photoId != edited.photoId { photoId = edited.photoId }
        if base.diceId != edited.diceId { diceId = edited.diceId }
        if base.groupId != edited.groupId { groupId = edited.groupId }
        if base.tablePlayers != edited.tablePlayers { tablePlayers = edited.tablePlayers }
    }
}
