// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import SwiftUI

struct OpenDiceIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Dice"

    @Parameter(title: "Dice", requestValueDialog: "Which die?")
    var target: DiceEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.dice(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenDiceIntent: TargetContentProvidingIntent {}
#endif

#endif
