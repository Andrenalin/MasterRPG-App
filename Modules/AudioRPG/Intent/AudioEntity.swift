// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI

struct AudioEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Audio"),
            numericFormat: "\(placeholder: .int) audios"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = AudioEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { displayName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { contentDescription }

    var icon: String { symbolName }

    private let displayName: String
    private let contentDescription: String
    private let symbolName: String
    
    @MainActor
    init(root: AudioRootModel, model: AudioModel) {
        id = model.id
        displayName = model.name
        contentDescription = model.description
        symbolName = model.specialCategory ? model.category.icon : root.config.module.icon
    }
}

extension AudioEntity: Transferable {
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
struct AudioEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: AudioRootModel
    private static let suggestedEntityLimit = 20
    private static let matchingEntityLimit = 25

    func suggestedEntities() async throws -> [AudioEntity] {
        let ids = root.itemController.itemDataModel.items.prefix(Self.suggestedEntityLimit)
        var results: [AudioEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [AudioEntity.ID]) async throws -> [AudioEntity] {
        var results: [AudioEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [AudioEntity] {
        guard !matching.isEmpty else { return try await suggestedEntities() }
        let ids = root.itemController.itemDataModel.items
        var results: [AudioEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.localizedStandardContains(matching) || model.description.localizedStandardContains(matching) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
            guard results.count < Self.matchingEntityLimit else { break }
        }
        return results
    }

    func allEntities() async throws -> [AudioEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [AudioEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension AudioEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AudioEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [AudioEntity.ID],
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

extension AudioEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "music.note.list"))
    }
}

#endif
