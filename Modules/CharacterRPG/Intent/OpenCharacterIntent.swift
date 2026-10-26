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

extension CharacterRootModel: SiriItemContext {
    public func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier? {
        EntityIdentifier(for: CharacterEntity.self, identifier: itemId)
    }

    public func siriOpenIntent(for itemId: UUID) -> (any AppIntent)? {
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

#endif
