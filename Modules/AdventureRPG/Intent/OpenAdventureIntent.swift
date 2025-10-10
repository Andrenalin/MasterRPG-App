// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

struct OpenAdventureIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Adventure"

    @Parameter(title: "Adventure", requestValueDialog: "Which Adventure?")
    var target: AdventureEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.adventures(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenAdventureIntent: TargetContentProvidingIntent {}
#endif

#endif
