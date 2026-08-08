// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import os.log
import SwiftUI


struct OpenGeneratorIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Generator"

    @Parameter(title: "Generator", requestValueDialog: "Which generator instructions?")
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

extension GeneratorRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: GeneratorEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenGeneratorIntent()
        intent.target = GeneratorEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenGeneratorIntent for Siri/Shortcuts: \(error.localizedDescription, privacy: .public)")
        }
#endif
    }
}

#endif
