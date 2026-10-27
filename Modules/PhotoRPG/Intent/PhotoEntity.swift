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
            numericFormat: "\(placeholder: .int) photos",
            synonyms: ["Picture", "Image"]
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = PhotoEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    /// The tags of the item, for Shortcuts and the Find action. See CODE_AUDIT_AppIntents §4.5.
    @ComputedProperty
    var tags: [String] { storedTags }

    @ComputedProperty
    var isFolder: Bool { storedIsFolder }

    /// A bounded excerpt of the entries' text, indexed so Spotlight matches words from the body.
    @ComputedProperty(indexingKey: \.textContent)
    var content: String { storedTextContent }

    let icon: String
    /// The folder or the first line of the description, see `IntentEntityText.subtitle`.
    let subtitle: String
    private let storedName: String
    private let storedDescription: String
    private let storedTags: [String]
    private let storedIsFolder: Bool
    private let storedTextContent: String

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
        self.storedTags = model.tags
        self.storedIsFolder = model.category == .folder
        self.storedTextContent = IntentEntityText.excerpt(of: model)
        self.subtitle = IntentEntityText.subtitle(of: model) { root.itemController.itemSync(for: $0) }
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when a `PhotoEntity`'s underlying stored photo can't be resolved
/// to a local file (e.g. the item has no attached file, or the file hasn't
/// finished downloading from iCloud yet).
struct PhotoEntityAssetUnavailableError: Error {}

/// The link the app already opens (`RPG://PHOTOS/0/<id>`), so a tapped Spotlight result opens the
/// item on every OS version. The literal must match `URL.appScheme` and
/// `NetworkModules.photo.token`; see `EntityUrlRepresentationTests`.
/// See CODE_AUDIT_AppIntents2 §4.1.
extension PhotoEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://PHOTOS/0/\(.id)"
    }
}

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

        DataRepresentation(exportedContentType: .plainText) { @MainActor item in
            EntitySummaryExport.plainText(id: item.id, module: .photo, name: item.name, description: item.description)
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
    func thumbnailData(root: PhotoRootModel, id: UUID) -> Data? {
        root.cacheController?.cachedThumbnail(for: id).flatMap { try? $0.pngRepresentationData() }
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension PhotoEntity: SyncableEntity {}

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
