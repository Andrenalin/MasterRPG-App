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

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.description }

    var icon: String {
        MainActor.assumeIsolated {
            model.specialCategory ? model.category.icon : root.config.module.icon
        }
    }

    var root: AudioRootModel
    var model: AudioModel
    
    init(root: AudioRootModel, model: AudioModel) {
        self.root = root
        self.model = model
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

    func suggestedEntities() async throws -> [AudioEntity] {
        let ids = root.itemController.itemDataModel.items
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
        let ids = root.itemController.itemDataModel.items
        var results: [AudioEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.contains(matching) || model.description.contains(matching) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [AudioEntity] {
        try await suggestedEntities()
    }
}

extension AudioEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "music.note.list"))
    }
}

#endif
