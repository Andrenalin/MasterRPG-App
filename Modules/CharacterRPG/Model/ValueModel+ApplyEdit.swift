// @copyright André Trettin

import CoreRPG
import Foundation

extension ValueModel {
    /// The editor window's forced save during a game: the photos, dice and group it changed
    /// reach the library too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: ValueModel, to edited: ValueModel) {
        if base.photoId != edited.photoId { photoId = edited.photoId }
        if base.photos != edited.photos { photos = edited.photos }
        if base.diceId != edited.diceId { diceId = edited.diceId }
        if base.groupId != edited.groupId { groupId = edited.groupId }
    }
}
