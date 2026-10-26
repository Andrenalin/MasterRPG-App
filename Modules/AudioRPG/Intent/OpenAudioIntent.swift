// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import os.log
import SwiftUI


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

extension AudioRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: AudioEntity.self, identifier: itemId)
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenAudioIntent()
        intent.target = AudioEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenAudioIntent for Siri/Shortcuts: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

#endif
