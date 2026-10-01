// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI

struct SpaceEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Space"),
            numericFormat: "\(placeholder: .int) 3D objects"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = SpaceEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: SpaceRootModel
    var model: SpaceModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: SpaceRootModel, model: SpaceModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when a `SpaceEntity`'s underlying stored 3D object can't be
/// resolved to a local file (e.g. the item has no attached file, or the
/// file hasn't finished downloading from iCloud yet).
struct SpaceEntityAssetUnavailableError: Error {}

extension SpaceEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Exports the actual stored USDZ file — not a rendered Name/
        // Description placeholder mislabeled as a PDF — so Shortcuts/Share
        // Sheet/drag-out hand the real 3D model to whatever consumes it.
        FileRepresentation(exportedContentType: .usdz) { @MainActor item in
            guard let url = await item.root.itemController.loadableUrl(itemId: item.id) else {
                throw SpaceEntityAssetUnavailableError()
            }
            return .init(url)
        }

        DataRepresentation(exportedContentType: .image) {
            try await $0.imageRepresentationData
        }

        DataRepresentation(exportedContentType: .plainText) {
            EntitySummaryExport.plainText(name: $0.name, description: $0.description)
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3.
@MainActor
struct SpaceEntityQuery: ItemEntityQuery {
    typealias Entity = SpaceEntity
    @Dependency var root: SpaceRootModel

    func makeEntity(root: SpaceRootModel, model: SpaceModel) -> SpaceEntity { SpaceEntity(root: root, model: model) }
    func allIds(root: SpaceRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: SpaceRootModel, id: UUID) -> SpaceModel? { root.itemController.itemSync(for: id) }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension SpaceEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension SpaceEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [SpaceEntity.ID],
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

extension SpaceEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "view.3d"))
    }
}

#endif
