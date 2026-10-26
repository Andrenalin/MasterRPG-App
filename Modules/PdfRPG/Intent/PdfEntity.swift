// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct PdfEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("PDF"),
            numericFormat: "\(placeholder: .int) PDFs"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = PdfEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: PdfRootModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // The live model is deliberately not stored: re-resolve it through the root when needed.
    // See CODE_AUDIT_AppIntents §3.1.
    @MainActor
    init(root: PdfRootModel, model: PdfModel) {
        self.root = root
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when a `PdfEntity`'s underlying stored PDF can't be resolved to a
/// local file (e.g. the item has no attached file, or the file hasn't
/// finished downloading from iCloud yet).
struct PdfEntityAssetUnavailableError: Error {}

extension PdfEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Exports the actual stored PDF file — not a rendered Name/
        // Description placeholder — so Shortcuts/Share Sheet/drag-out hand
        // the real document to whatever consumes it.
        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            guard let url = await item.root.itemController.loadableUrl(itemId: item.id) else {
                throw PdfEntityAssetUnavailableError()
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
struct PdfEntityQuery: ItemEntityQuery {
    typealias Entity = PdfEntity
    @Dependency var root: PdfRootModel

    func makeEntity(root: PdfRootModel, model: PdfModel) -> PdfEntity { PdfEntity(root: root, model: model) }
    func allIds(root: PdfRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: PdfRootModel, id: UUID) -> PdfModel? { root.itemController.itemSync(for: id) }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension PdfEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension PdfEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [PdfEntity.ID],
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
