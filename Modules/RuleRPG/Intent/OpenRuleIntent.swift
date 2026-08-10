// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation
import os.log

struct OpenRuleIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Rule"

    @Parameter(title: "Rule", requestValueDialog: "Which rule?")
    var target: RuleEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.rules(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenRuleIntent: TargetContentProvidingIntent {}
#endif

extension RuleRootModel {
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId),
              !model.specialCategory else { return }
        activity.appEntityIdentifier = EntityIdentifier(
            for: RuleEntity.self,
            identifier: itemId
        )
#endif
    }

    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId),
              !model.specialCategory else { return }
        let intent = OpenRuleIntent()
        intent.target = RuleEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenRuleIntent for Siri/Shortcuts: \(error.localizedDescription, privacy: .public)")
        }
#endif
    }
}

#endif
