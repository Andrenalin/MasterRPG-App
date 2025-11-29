// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreExternalRPG
import Foundation
import SwiftUI

struct OpenTableIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Table"

    @Parameter(title: "Table", requestValueDialog: "Which Table?")
    var target: TableEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.tables(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenTableIntent: TargetContentProvidingIntent {}
#endif

#endif
