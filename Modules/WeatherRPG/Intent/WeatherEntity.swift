// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct WeatherEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Weather"),
            numericFormat: "\(placeholder: .int) Weather"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = WeatherEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // Unlike sibling *Entity types with a file-backed Transferable (e.g. PdfEntity),
    // this entity never needs live access to `root`/`model` after init, so neither
    // is retained as a stored property.
    @MainActor
    init(root: WeatherRootModel, model: WeatherModel) {
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when the `WeatherEntity` PDF export can't open a `CGContext` for the
/// destination file (e.g. disk full, sandbox/permission issue).
struct WeatherEntityPdfRenderingError: Error {}

extension WeatherEntity: Transferable {
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
struct WeatherEntityQuery: ItemEntityQuery {
    typealias Entity = WeatherEntity
    @Dependency var root: WeatherRootModel

    func makeEntity(root: WeatherRootModel, model: WeatherModel) -> WeatherEntity { WeatherEntity(root: root, model: model) }
    func allIds(root: WeatherRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: WeatherRootModel, id: UUID) -> WeatherModel? { root.itemController.itemSync(for: id) }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension WeatherEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension WeatherEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [WeatherEntity.ID],
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

extension WeatherEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "cloud.bolt.rain"))
    }
}

#endif
