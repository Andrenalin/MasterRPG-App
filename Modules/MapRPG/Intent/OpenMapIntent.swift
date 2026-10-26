// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

struct OpenMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Map"
    static let supportedModes: IntentModes = .foreground

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

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenMapIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenMapSchemaIntent: OpenIntent {
    var target: MapEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.maps(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenMapSchemaIntent: TargetContentProvidingIntent {}
#endif

extension MapRootModel {
    @MainActor
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = EntityIdentifier(for: MapEntity.self, identifier: itemId)
    }

    @MainActor
    /// Donates the open intent that matches the running OS, once the item stays selected.
    /// See CODE_AUDIT_AppIntents §4.4.
    func donateSiriViewingIntent(for itemId: UUID) async {
        await IntentDonations.donateOpen(of: itemId) { [self] () -> (any AppIntent)? in
            guard let model = itemController.itemSync(for: itemId) else { return nil }
            let entity = MapEntity(root: self, model: model)
            if #available(iOS 27, macOS 27, visionOS 27, *) {
                let intent = OpenMapSchemaIntent()
                intent.target = entity
                return intent
            }
            let intent = OpenMapIntent()
            intent.target = entity
            return intent
        }
    }
}

#endif
