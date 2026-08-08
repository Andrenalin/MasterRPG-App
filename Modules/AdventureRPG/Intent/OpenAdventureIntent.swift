// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

public struct OpenAdventureIntent: OpenIntent {
    public static let title: LocalizedStringResource = "Open Adventure"

    @Parameter(title: "Adventure", requestValueDialog: "Which Adventure?")
    public var target: AdventureEntity

    @Dependency var navigator: Navigator

    public init() {}

    public func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.adventures(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenAdventureIntent: TargetContentProvidingIntent {}
#endif

extension AdventureRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: AdventureEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        let intent = OpenAdventureIntent()
        intent.target = AdventureEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {
            Logger.appIntents.debug("Failed to donate OpenAdventureIntent for Siri/Shortcuts: \(error.localizedDescription, privacy: .public)")
        }
#endif
    }
}

#endif
