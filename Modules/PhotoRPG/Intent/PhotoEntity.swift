// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct PhotoEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Photo"),
            numericFormat: "\(placeholder: .int) photos"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = PhotoEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: PhotoRootModel
    var model: PhotoModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: PhotoRootModel, model: PhotoModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when a `PhotoEntity`'s underlying stored photo can't be resolved
/// to a local file (e.g. the item has no attached file, or the file hasn't
/// finished downloading from iCloud yet).
struct PhotoEntityAssetUnavailableError: Error {}

extension PhotoEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Exports the actual stored photo file — not a rendered Name/
        // Description placeholder — so Shortcuts/Share Sheet/drag-out hand
        // the real image to whatever consumes it.
        FileRepresentation(exportedContentType: .jpeg) { @MainActor item in
            guard let url = await item.root.itemController.loadableUrl(itemId: item.id) else {
                throw PhotoEntityAssetUnavailableError()
            }
            return .init(url)
        }

        DataRepresentation(exportedContentType: .image) {
            try await $0.imageRepresentationData
        }

        DataRepresentation(exportedContentType: .plainText) {
            Data(
                """
                Name: \($0.name)
                Description: \($0.description)
                """.utf8
            )
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3.
@MainActor
struct PhotoEntityQuery: ItemEntityQuery {
    typealias Entity = PhotoEntity
    @Dependency var root: PhotoRootModel

    func makeEntity(root: PhotoRootModel, model: PhotoModel) -> PhotoEntity { PhotoEntity(root: root, model: model) }
    func allIds(root: PhotoRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: PhotoRootModel, id: UUID) -> PhotoModel? { root.itemController.itemSync(for: id) }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension PhotoEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension PhotoEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [PhotoEntity.ID],
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

extension PhotoEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: NetworkModules.photo.icon))
    }
}

#endif
