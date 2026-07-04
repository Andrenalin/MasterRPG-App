// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

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

extension TableRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: TableEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenTableIntent()
        intent.target = TableEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {}
#endif
    }
}

#endif
