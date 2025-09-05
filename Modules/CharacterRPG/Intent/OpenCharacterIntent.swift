// @copyright André Trettin

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

struct OpenCharacterIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Character"

    @Parameter(title: "Character", requestValueDialog: "Which Character?")
    var target: CharacterEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.values(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenCharacterIntent: TargetContentProvidingIntent {}
#endif
