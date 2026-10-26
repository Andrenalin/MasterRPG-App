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
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        guard let model = itemController.itemSync(for: itemId),
              !model.specialCategory else { return }
        activity.appEntityIdentifier = EntityIdentifier(
            for: RuleEntity.self,
            identifier: itemId
        )
    }

    /// `IntentDonationManager` is available since iOS 16 / macOS 13. See CODE_AUDIT_AppIntents §5.1.
    func donateSiriViewingIntent(for itemId: UUID) async {
        guard let model = itemController.itemSync(for: itemId),
              !model.specialCategory else { return }
        let intent = OpenRuleIntent()
        intent.target = RuleEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenRuleIntent for Siri/Shortcuts: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

#endif
