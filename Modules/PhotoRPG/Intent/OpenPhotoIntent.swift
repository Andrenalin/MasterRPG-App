// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import Foundation
import SwiftUI
import CoreRPG
import CoreExternalRPG

struct OpenPhotoIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Photo"

    @Parameter(title: "Photo", requestValueDialog: "Which photo?")
    var target: PhotoEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.photos(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenPhotoIntent: TargetContentProvidingIntent {}
#endif

#endif
