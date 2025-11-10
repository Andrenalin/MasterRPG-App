// @copyright André Trettin

#if !os(tvOS)

import AndrenalinKit
import AppIntents
import Foundation
import SwiftUI
import CoreExternalRPG

struct OpenAudioIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Audio"

    @Parameter(title: "Audio", requestValueDialog: "Which audio?")
    var target: AudioEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.audios(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenAudioIntent: TargetContentProvidingIntent {}
#endif

#endif
