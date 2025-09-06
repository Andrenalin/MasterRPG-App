// @copyright André Trettin

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

struct OpenMapIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Map"

    @Parameter(title: "Map", requestValueDialog: "Which Map?")
    var target: MapEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.maps(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenMapIntent: TargetContentProvidingIntent {}
#endif
