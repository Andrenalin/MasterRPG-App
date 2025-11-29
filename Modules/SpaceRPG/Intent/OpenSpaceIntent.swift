// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreExternalRPG
import Foundation
import SwiftUI

struct OpenSpaceIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open 3D Object"

    @Parameter(title: "Space", requestValueDialog: "Which 3D object?")
    var target: SpaceEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.spaces(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenSpaceIntent: TargetContentProvidingIntent {}
#endif

#endif
