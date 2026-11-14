// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreRPG
import CoreSpotlight
import CoreTransferable
import Foundation
import SwiftUI

struct RuleEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: "Rule",
            numericFormat: "\(placeholder: .int) rules",
            synonyms: ["Compendium"]
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = RuleEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    /// The tags of the item, for Shortcuts and the Find action. See CODE_AUDIT_AppIntents §4.5.
    @ComputedProperty
    var tags: [String] { storedTags }

    @ComputedProperty
    var isFolder: Bool { storedIsFolder }

    /// A bounded excerpt of the entries' text, indexed so Spotlight matches words from the body.
    @ComputedProperty(indexingKey: \.textContent)
    var content: String { storedTextContent }

    let icon: String
    /// The folder or the first line of the description, see `IntentEntityText.subtitle`.
    let subtitle: String
    private let storedName: String
    private let storedDescription: String
    private let storedTags: [String]
    private let storedIsFolder: Bool
    private let storedTextContent: String
    /// Kept for the exports; the item model is re-resolved through it, never stored.
    /// See CODE_AUDIT_AppIntents3 §9.1.
    var root: RuleRootModel

    @MainActor
    init(root: RuleRootModel, model: RuleModel) {
        self.root = root
        id = model.id
        storedName = model.name
        storedDescription = model.description
        storedTags = model.tags
        storedIsFolder = model.category == .folder
        storedTextContent = IntentEntityText.excerpt(of: model)
        subtitle = IntentEntityText.subtitle(of: model) { root.itemController.itemSync(for: $0) }
        icon = model.specialCategory ? model.category.icon : NetworkModules.rule.icon
    }
}

/// The link the app already opens (`RPG://RULES/0/<id>`), so a tapped Spotlight result opens the
/// item on every OS version. The literal must match `URL.appScheme` and
/// `NetworkModules.rule.token`; see `EntityUrlRepresentationTests`.
/// See CODE_AUDIT_AppIntents2 §4.1.
extension RuleEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://RULES/0/\(.id)"
    }
}

/// Name, description and sections, through the document `RuleIntentSupport` registers; the live
/// model is looked up there instead of being stored on the entity. See CODE_AUDIT_AppIntents §3.1,
/// CODE_AUDIT_AppIntents3 §4.1.
extension RuleEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { @MainActor item in
            EntitySummaryExport.plainText(id: item.id, module: .rule, name: item.name, description: item.description)
        }

        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            .init(try await EntitySummaryExport.pdf(id: item.id, module: .rule, name: item.name, description: item.description))
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3. Rule is one
// of the two modules that needs real overrides: `include(model:)` excludes
// `specialCategory` items everywhere (`entities(for:)` included — a
// `specialCategory` item is never a valid Siri/Shortcuts/Spotlight result),
// and `suggestedEntities()` keeps its own control flow, which — unlike
// every other module — prefixes to the limit *after* filtering rather than
// before, so a `specialCategory` item earlier in `itemDataModel.items`
// doesn't itself count against the limit.
@MainActor
struct RuleEntityQuery: ItemEntityQuery {
    typealias Entity = RuleEntity
    @Dependency var root: RuleRootModel

    func makeEntity(root: RuleRootModel, model: RuleModel) -> RuleEntity { RuleEntity(root: root, model: model) }
    func allIds(root: RuleRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: RuleRootModel, id: UUID) -> RuleModel? { root.itemController.itemSync(for: id) }
    func include(model: RuleModel) -> Bool {
        !model.specialCategory && !model.isHidden
    }

    func suggestedEntities() async throws -> [RuleEntity] {
        await DatabaseReadiness.wait()
        var entities: [RuleEntity] = []
        for id in allIds(root: root) {
            guard let model = model(root: root, id: id), include(model: model) else { continue }
            entities.append(makeEntity(root: root, model: model))
            guard entities.count < Self.suggestedLimit else { break }
        }
        return entities
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension RuleEntity: SyncableEntity {}

@available(iOS 27, macOS 27, visionOS 27, *)
extension RuleEntityQuery: @preconcurrency IndexedEntityQuery {}
#endif
