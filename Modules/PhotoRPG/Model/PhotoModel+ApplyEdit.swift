// @copyright André Trettin

import CoreRPG
import Foundation

extension PhotoModel {
    /// The editor window's forced save during a game: a changed rotation reaches the library
    /// too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: PhotoModel, to edited: PhotoModel) {
        if base.degrees != edited.degrees { degrees = edited.degrees }
    }
}
