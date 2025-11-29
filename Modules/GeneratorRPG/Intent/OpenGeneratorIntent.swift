// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import SwiftUI


struct OpenGeneratorIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Generator"

    @Parameter(title: "Generator", requestValueDialog: "Which generator intructions?")
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

#endif
