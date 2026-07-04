// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import SwiftUI

struct OpenCharacterIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Character"

    @Parameter(title: "Character", requestValueDialog: "Which Character?")
    var target: CharacterEntity

    @Dependency var navigator: Navigator

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
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: CharacterEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenCharacterIntent()
        intent.target = CharacterEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {}
#endif
    }
}

#endif
