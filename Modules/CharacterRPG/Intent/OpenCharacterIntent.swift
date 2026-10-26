// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

struct OpenCharacterIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Character"

    @Parameter(title: "Character", requestValueDialog: "Which Character?")
    var target: CharacterEntity

    @Dependency var navigator: Navigator

    @MainActor
    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.values(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenCharacterIntent: TargetContentProvidingIntent {}
#endif

extension CharacterRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: CharacterEntity.self, identifier: itemId)
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenCharacterIntent()
        intent.target = CharacterEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenCharacterIntent for Siri/Shortcuts: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

#endif
