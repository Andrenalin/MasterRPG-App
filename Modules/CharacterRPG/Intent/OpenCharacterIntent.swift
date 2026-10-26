// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

struct OpenCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Character"
    static let supportedModes: IntentModes = .foreground

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

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenCharacterIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenCharacterSchemaIntent: OpenIntent {
    var target: CharacterEntity

    @Dependency var navigator: Navigator

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.values(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenCharacterSchemaIntent: TargetContentProvidingIntent {}
#endif

extension CharacterRootModel {
    @MainActor
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = EntityIdentifier(for: CharacterEntity.self, identifier: itemId)
    }

    @MainActor
    /// Donates the open intent that matches the running OS, once the item stays selected.
    /// See CODE_AUDIT_AppIntents §4.4.
    func donateSiriViewingIntent(for itemId: UUID) async {
        await IntentDonations.donateOpen(of: itemId) { [self] () -> (any AppIntent)? in
            guard let model = itemController.itemSync(for: itemId) else { return nil }
            let entity = CharacterEntity(root: self, model: model)
            if #available(iOS 27, macOS 27, visionOS 27, *) {
                let intent = OpenCharacterSchemaIntent()
                intent.target = entity
                return intent
            }
            let intent = OpenCharacterIntent()
            intent.target = entity
            return intent
        }
    }
}

#endif
