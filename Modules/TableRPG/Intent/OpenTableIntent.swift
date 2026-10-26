// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

struct OpenTableIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Table"

    @Parameter(title: "Table", requestValueDialog: "Which table?")
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

extension TableRootModel {
    @MainActor
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = EntityIdentifier(for: TableEntity.self, identifier: itemId)
    }

    @MainActor
    /// `IntentDonationManager` is available since iOS 16 / macOS 13. See CODE_AUDIT_AppIntents §5.1.
    func donateSiriViewingIntent(for itemId: UUID) async {
        guard let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenTableIntent()
        intent.target = TableEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenTableIntent for Siri/Shortcuts: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }
}

#endif
