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
            numericFormat: "\(placeholder: .int) rules"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: icon))
    }

    static let defaultQuery = RuleEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String
    var root: RuleRootModel

    @MainActor
    init(root: RuleRootModel, model: RuleModel) {
        self.root = root
        id = model.id
        storedName = model.name
        storedDescription = model.description
        icon = model.specialCategory ? model.category.icon : NetworkModules.rule.icon
    }
}

extension RuleEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { item in
            await item.exportedPlainText()
        }
    }
}

extension RuleEntity {
    /// Name, description and sections as plain text. The live model is looked up here instead of
    /// being stored on the entity; a rule that no longer exists still exports its name and
    /// description, a special category exports nothing. See CODE_AUDIT_AppIntents §3.1.
    @MainActor
    fileprivate func exportedPlainText() -> Data {
        let model = root.itemController.itemSync(for: id)
        guard model?.specialCategory != true else { return Data() }
        var result = "\(name)\n\n\(description)"
        for entry in model?.entries ?? [] {
            result += "\n\n\(entry.name)\n\(entry.content)"
        }
        return result.data(using: .utf8) ?? Data()
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
        !model.specialCategory && model.displayState != DisplayStateMask.totalHidden.rawValue
    }

    func suggestedEntities() async throws -> [RuleEntity] {
        await DatabaseReadiness.wait()
        let entities: [RuleEntity] = allIds(root: root).compactMap { id -> RuleEntity? in
            guard let model = model(root: root, id: id), include(model: model) else { return nil }
            return makeEntity(root: root, model: model)
        }
        return Array(entities.prefix(Self.suggestedLimit))
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension RuleEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension RuleEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [UUID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        try await CSSearchableIndex.default().indexAppEntities(
            try await entities(for: identifiers)
        )
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await CSSearchableIndex.default().indexAppEntities(try await allEntities())
    }
}
#endif
