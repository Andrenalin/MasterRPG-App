// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import Foundation

struct OpenRuleIntent: AppIntent, ItemOpenIntent {
    static let title: LocalizedStringResource = "Open Rule"
    static let description = IntentDescription(
        "Opens a rule in the app.",
        categoryName: "Rule",
        searchKeywords: ["show", "compendium", "rulebook"]
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Rule", requestValueDialog: .localized("Which rule?", bundle: .ruleModule))
    var target: RuleEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await openTarget()
        return .result()
    }
}

#if os(iOS)
extension OpenRuleIntent: TargetContentProvidingIntent {}
#endif

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenRuleIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenRuleSchemaIntent: OpenIntent, ItemOpenIntent {
    /// Serves Siri and Spotlight; the legacy open intent is the one Shortcuts lists, so the library
    /// does not show two "open" actions per module. See CODE_AUDIT_AppIntents2 §4.2.
    static let isDiscoverable = false

    var target: RuleEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await openTarget()
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenRuleSchemaIntent: TargetContentProvidingIntent {}
#endif

extension RuleRootModel: SiriItemContext {
    public func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier? {
        guard let model = itemController.itemSync(for: itemId),
              !model.specialCategory else { return nil }
        return EntityIdentifier(for: RuleEntity.self, identifier: itemId)
    }

    public func siriOpenIntent(for itemId: UUID) -> (any AppIntent)? {
        guard let model = itemController.itemSync(for: itemId),
              !model.specialCategory else { return nil }
        let entity = RuleEntity(root: self, model: model)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            return OpenRuleSchemaIntent.opening(entity)
        }
        return OpenRuleIntent.opening(entity)
    }
}

#endif
