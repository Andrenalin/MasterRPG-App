// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import SwiftUI

struct OpenDiceIntent: AppIntent, ItemOpenIntent {
    static let title: LocalizedStringResource = "Open Dice"
    static let description = IntentDescription(
        "Opens a dice in the app.",
        categoryName: "Dice",
        searchKeywords: ["show", "die", "roll"]
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Dice", requestValueDialog: .localized("Which die?", bundle: .module))
    var target: DiceEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await openTarget()
        return .result()
    }
}

#if os(iOS)
extension OpenDiceIntent: TargetContentProvidingIntent {}
#endif

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenDiceIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenDiceSchemaIntent: OpenIntent, ItemOpenIntent {
    /// Serves Siri and Spotlight; the legacy open intent is the one Shortcuts lists, so the library
    /// does not show two "open" actions per module. See CODE_AUDIT_AppIntents2 §4.2.
    static let isDiscoverable = false

    var target: DiceEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await openTarget()
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenDiceSchemaIntent: TargetContentProvidingIntent {}
#endif

extension DiceRootModel: SiriItemContext {
    public func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier? {
        EntityIdentifier(for: DiceEntity.self, identifier: itemId)
    }

    public func siriOpenIntent(for itemId: UUID) -> (any AppIntent)? {
        guard let model = itemController.itemSync(for: itemId) else { return nil }
        let entity = DiceEntity(root: self, model: model)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            return OpenDiceSchemaIntent.opening(entity)
        }
        return OpenDiceIntent.opening(entity)
    }
}

#endif
