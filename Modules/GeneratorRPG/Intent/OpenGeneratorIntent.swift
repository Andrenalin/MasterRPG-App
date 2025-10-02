// @copyright André Trettin

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

struct OpenGeneratorIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Generator"

    @Parameter(title: "Space", requestValueDialog: "Which generator intructions?")
    var target: GeneratorEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.generators(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenGeneratorIntent: TargetContentProvidingIntent {}
#endif
