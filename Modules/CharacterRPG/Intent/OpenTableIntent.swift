// @copyright André Trettin

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

struct OpenTableIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Weather"

    @Parameter(title: "Weather", requestValueDialog: "Which Weather?")
    var target: TableEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.weathers(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenTableIntent: TargetContentProvidingIntent {}
#endif
