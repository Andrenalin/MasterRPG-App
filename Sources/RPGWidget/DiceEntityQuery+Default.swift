// @copyright André Trettin

import AppIntents
import DiceRPG
import WidgetKit

public extension DiceEntityQuery {
    func defaultResult() async -> DiceWidgetIntentEntity? {
        try? await suggestedEntities().first
    }
}
