// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct CharacterEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Character"),
            numericFormat: "\(placeholder: .int) Character"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = CharacterEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: CharacterRootModel
    var model: ValueModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: CharacterRootModel, model: ValueModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

extension CharacterEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            .init(try EntitySummaryExport.pdf(id: item.id, name: item.name, description: item.description))
        }

        DataRepresentation(exportedContentType: .plainText) {
            EntitySummaryExport.plainText(name: $0.name, description: $0.description)
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3.
@MainActor
struct CharacterEntityQuery: ItemEntityQuery {
    typealias Entity = CharacterEntity
    @Dependency var root: CharacterRootModel

    func makeEntity(root: CharacterRootModel, model: ValueModel) -> CharacterEntity { CharacterEntity(root: root, model: model) }
    func allIds(root: CharacterRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: CharacterRootModel, id: UUID) -> ValueModel? { root.itemController.itemSync(for: id) }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension CharacterEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension CharacterEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [CharacterEntity.ID],
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
