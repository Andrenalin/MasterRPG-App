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
            name: LocalizedStringResource("Generator"),
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

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.description }

    var icon: String {
        model.specialCategory ? model.category.icon : root.config.module.icon
    }
    
    var root: GeneratorRootModel
    var model: GeneratorModel
    
    init(root: GeneratorRootModel, model: GeneratorModel) {
        self.root = root
        self.model = model
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

    func suggestedEntities() async throws -> [GeneratorEntity] {
        let ids = root.itemController.itemDataModel.items
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
        let ids = root.itemController.itemDataModel.items
        var results: [GeneratorEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.localizedStandardContains(matching) || model.description.localizedStandardContains(matching) else { continue }
            let entity = GeneratorEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [GeneratorEntity] {
        try await suggestedEntities()
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
