// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct GeneratorEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: "Generator",
            numericFormat: "\(placeholder: .int) Instructions"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = GeneratorEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: GeneratorRootModel
    var model: GeneratorModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: GeneratorRootModel, model: GeneratorModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

extension GeneratorEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) {
            """
            Name: \($0.name)
            Description: \($0.description)
            """.data(using: .utf8)!
        }
    }
}

@MainActor
struct GeneratorEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: GeneratorRootModel
    private static let suggestedEntityLimit = 20
    private static let matchingEntityLimit = 25

    func suggestedEntities() async throws -> [GeneratorEntity] {
        let ids = root.itemController.itemDataModel.items.prefix(Self.suggestedEntityLimit)
        var results: [GeneratorEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = GeneratorEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [GeneratorEntity.ID]) async throws -> [GeneratorEntity] {
        var results: [GeneratorEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = GeneratorEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [GeneratorEntity] {
        guard !matching.isEmpty else { return try await suggestedEntities() }
        let ids = root.itemController.itemDataModel.items
        var results: [GeneratorEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.localizedStandardContains(matching) || model.description.localizedStandardContains(matching) else { continue }
            let entity = GeneratorEntity(root: root, model: model)
            results.append(entity)
            guard results.count < Self.matchingEntityLimit else { break }
        }
        return results
    }

    func allEntities() async throws -> [GeneratorEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [GeneratorEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = GeneratorEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension GeneratorEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension GeneratorEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [GeneratorEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let all = try await allEntities()
        try await CSSearchableIndex.default().indexAppEntities(all)
    }
}
#endif

extension GeneratorEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "apple.intelligence"))
    }
}

#endif
