// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

public struct OpenAdventureIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Adventure"
    public static let supportedModes: IntentModes = .foreground

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

/// The iOS 27 open intent. `.system.open` is what lets Siri resolve "open <name> in MasterRPG"
/// against the indexed adventures; the schema supplies the title and the `target` parameter. It
/// is a sibling of `OpenAdventureIntent` (the macro and schema are 27-only) and takes the same
/// route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
public struct OpenAdventureSchemaIntent: OpenIntent {
    public var target: AdventureEntity

    @Dependency var navigator: Navigator

    public init() {}

    public func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.adventures(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenAdventureSchemaIntent: TargetContentProvidingIntent {}
#endif

extension AdventureRootModel {
    @MainActor
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = EntityIdentifier(for: AdventureEntity.self, identifier: itemId)
    }

    @MainActor
    /// Donates the open intent that matches the running OS, once the item stays selected.
    /// See CODE_AUDIT_AppIntents §4.4.
    func donateSiriViewingIntent(for itemId: UUID) async {
        await IntentDonations.donateOpen(of: itemId) { [self] () -> (any AppIntent)? in
            guard let model = itemController.itemSync(for: itemId) else { return nil }
            let entity = AdventureEntity(root: self, model: model)
            if #available(iOS 27, macOS 27, visionOS 27, *) {
                let intent = OpenAdventureSchemaIntent()
                intent.target = entity
                return intent
            }
            let intent = OpenAdventureIntent()
            intent.target = entity
            return intent
        }
    }
}

#endif
