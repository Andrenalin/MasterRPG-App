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
    var model: RuleModel

    @MainActor
    init(root: RuleRootModel, model: RuleModel) {
        self.root = root
        self.model = model
        id = model.id
        storedName = model.name
        storedDescription = model.description
        icon = model.specialCategory ? model.category.icon : NetworkModules.rule.icon
    }
}

extension RuleEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { item in
            let isSpecialCategory = await item.model.specialCategory
            guard !isSpecialCategory else { return Data() }
            var result = "\(item.name)\n\n\(item.description)"
            let sections = await item.model.entries.map { entry in
                "\n\n\(entry.name)\n\(entry.content)"
            }.joined()
            result += sections
            return result.data(using: .utf8) ?? Data()
        }
    }
}

@MainActor
struct RuleEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: RuleRootModel
    private static let suggestedLimit = 20
    private static let matchingLimit = 25

    func suggestedEntities() async throws -> [RuleEntity] {
        let entities: [RuleEntity] = root.itemController.itemDataModel.items.compactMap { id -> RuleEntity? in
            guard let model = root.itemController.itemSync(for: id), !model.specialCategory else {
                return nil
            }
            return RuleEntity(root: root, model: model)
        }
        return Array(entities.prefix(Self.suggestedLimit))
    }

    func entities(for identifiers: [UUID]) async throws -> [RuleEntity] {
        identifiers.compactMap { id -> RuleEntity? in
            guard let model = root.itemController.itemSync(for: id), !model.specialCategory else {
                return nil
            }
            return RuleEntity(root: root, model: model)
        }
    }

    func entities(matching text: String) async throws -> [RuleEntity] {
        guard !text.isEmpty else { return try await suggestedEntities() }
        var results: [RuleEntity] = []
        for id in root.itemController.itemDataModel.items {
            guard let model = root.itemController.itemSync(for: id),
                  !model.specialCategory,
                  model.name.localizedStandardContains(text) ||
                    model.description.localizedStandardContains(text) else { continue }
            results.append(RuleEntity(root: root, model: model))
            if results.count >= Self.matchingLimit { break }
        }
        return results
    }

    func allEntities() async throws -> [RuleEntity] {
        root.itemController.itemDataModel.items.compactMap { id -> RuleEntity? in
            guard let model = root.itemController.itemSync(for: id), !model.specialCategory else {
                return nil
            }
            return RuleEntity(root: root, model: model)
        }
    }
}

#if compiler(>=6.4)
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

extension RuleEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: NetworkModules.rule.icon))
    }
}

#endif
