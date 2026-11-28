// @copyright André Trettin

import CoreRPG
import Foundation

extension RuleModel {
    /// The editor window's forced save during a game: changed source metadata reaches the
    /// library too. See `ItemDataAccessible.applyEdit(from:to:)`.
    public func applyModuleEdit(from base: RuleModel, to edited: RuleModel) {
        if base.sourceMetadata != edited.sourceMetadata { sourceMetadata = edited.sourceMetadata }
        if base.sourcePayload != edited.sourcePayload { sourcePayload = edited.sourcePayload }
    }
}
