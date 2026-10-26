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

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // The live model is deliberately not stored: re-resolve it through the root when needed.
    // See CODE_AUDIT_AppIntents §3.1.
    @MainActor
    init(root: PhotoRootModel, model: PhotoModel) {
        self.root = root
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
        // the real image to whatever consumes it. Declared as the abstract
        // `.image` type (not `.jpeg`): not every import path converts to JPEG
        // (see `EditController.isNotJpegPhoto`), so a fixed `.jpeg` UTI would
        // mismatch the actual bytes for PNG/HEIC/TIFF-sourced photos. See
        // CODE_AUDIT §5.2.
        FileRepresentation(exportedContentType: .image) { @MainActor item in
            guard let url = await item.root.itemController.loadableUrl(itemId: item.id) else {
                throw PhotoEntityAssetUnavailableError()
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
struct PhotoEntityQuery: ItemEntityQuery {
    typealias Entity = PhotoEntity
    @Dependency var root: PhotoRootModel

    func makeEntity(root: PhotoRootModel, model: PhotoModel) -> PhotoEntity { PhotoEntity(root: root, model: model) }
    func allIds(root: PhotoRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: PhotoRootModel, id: UUID) -> PhotoModel? { root.itemController.itemSync(for: id) }
}

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
