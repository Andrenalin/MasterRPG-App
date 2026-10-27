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
            numericFormat: "\(placeholder: .int) 3D objects",
            synonyms: ["3D model", "Miniature"]
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

    /// The tags of the item, for Shortcuts and the Find action. See CODE_AUDIT_AppIntents §4.5.
    @ComputedProperty
    var tags: [String] { storedTags }

    @ComputedProperty
    var isFolder: Bool { storedIsFolder }

    /// A bounded excerpt of the entries' text, indexed so Spotlight matches words from the body.
    @ComputedProperty(indexingKey: \.textContent)
    var content: String { storedTextContent }

    let icon: String
    private let storedName: String
    private let storedDescription: String
    private let storedTags: [String]
    private let storedIsFolder: Bool
    private let storedTextContent: String

    var root: SpaceRootModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // The live model is deliberately not stored: re-resolve it through the root when needed.
    // See CODE_AUDIT_AppIntents §3.1.
    @MainActor
    init(root: SpaceRootModel, model: SpaceModel) {
        self.root = root
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        self.storedTags = model.tags
        self.storedIsFolder = model.category == .folder
        self.storedTextContent = IntentEntityText.excerpt(of: model)
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when a `SpaceEntity`'s underlying stored 3D object can't be
/// resolved to a local file (e.g. the item has no attached file, or the
/// file hasn't finished downloading from iCloud yet).
struct SpaceEntityAssetUnavailableError: Error {}

/// The link the app already opens (`RPG://SPACES/0/<id>`), so a tapped Spotlight result opens the
/// item on every OS version. The literal must match `URL.appScheme` and
/// `NetworkModules.space.token`; see `EntityUrlRepresentationTests`.
/// See CODE_AUDIT_AppIntents2 §4.1.
extension SpaceEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://SPACES/0/\(.id)"
    }
}

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
    func thumbnailData(root: SpaceRootModel, id: UUID) -> Data? {
        root.cacheController?.cachedThumbnail(for: id).flatMap { try? $0.pngRepresentationData() }
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension SpaceEntity: SyncableEntity {}

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
