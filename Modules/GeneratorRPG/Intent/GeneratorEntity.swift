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
        model.specialCategory ? model.category.icon : root.module.icon
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
            guard model.name.contains(matching) || model.description.contains(matching) else { continue }
            let entity = GeneratorEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [GeneratorEntity] {
        try await suggestedEntities()
    }
}

extension GeneratorEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "apple.intelligence"))
    }
}

#endif
