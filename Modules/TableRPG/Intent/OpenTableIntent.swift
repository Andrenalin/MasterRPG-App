// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

struct OpenTableIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Table"
    static let description = IntentDescription(
        "Opens a table in the app.",
        categoryName: "Table",
        searchKeywords: ["show", "random table", "loot"]
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Table", requestValueDialog: .localized("Which table?", bundle: .module))
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

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenTableIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenTableSchemaIntent: OpenIntent {
    /// Serves Siri and Spotlight; the legacy open intent is the one Shortcuts lists, so the library
    /// does not show two "open" actions per module. See CODE_AUDIT_AppIntents2 §4.2.
    static let isDiscoverable = false

    var target: TableEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.tables(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenTableSchemaIntent: TargetContentProvidingIntent {}
#endif

extension TableRootModel: SiriItemContext {
    public func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier? {
        EntityIdentifier(for: TableEntity.self, identifier: itemId)
    }

    public func siriOpenIntent(for itemId: UUID) -> (any AppIntent)? {
        guard let model = itemController.itemSync(for: itemId) else { return nil }
        let entity = TableEntity(root: self, model: model)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            let intent = OpenTableSchemaIntent()
            intent.target = entity
            return intent
        }
        let intent = OpenTableIntent()
        intent.target = entity
        return intent
    }
}

#endif
