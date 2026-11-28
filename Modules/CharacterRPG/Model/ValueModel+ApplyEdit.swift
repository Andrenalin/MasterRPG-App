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

extension ValueEntryModel {
    /// Field by field: renaming an entry in the editor window during a game no longer persists
    /// the value it has in the game, and a field another device changed meanwhile is kept.
    /// See CODE_AUDIT_Edit_Save §5.11.
    public mutating func applyEdit(from base: ValueEntryModel, to edited: ValueEntryModel) {
        if base.name != edited.name { name = edited.name }
        if base.type != edited.type { type = edited.type }
        if base.isGenerator != edited.isGenerator { isGenerator = edited.isGenerator }
        if base.value != edited.value { value = edited.value }
        if base.diceId != edited.diceId { diceId = edited.diceId }
        if base.valueId != edited.valueId { valueId = edited.valueId }
        if base.displayState != edited.displayState { displayState = edited.displayState }
    }
}
