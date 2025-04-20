// @copyright André Trettin

import AppIntents
import RPGDie
import WidgetKit

public extension DiceEntityQuery {
    func defaultResult() async -> DiceWidgetIntentEntity? {
        try? await suggestedEntities().first
    }
}
