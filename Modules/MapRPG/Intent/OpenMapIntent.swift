// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import SwiftUI

struct OpenMapIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Map"

    @Parameter(title: "Map", requestValueDialog: "Which Map?")
    var target: MapEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.maps(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenMapIntent: TargetContentProvidingIntent {}
#endif

extension MapRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: MapEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        var intent = OpenMapIntent()
        intent.target = MapEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {}
#endif
    }
}

#endif
