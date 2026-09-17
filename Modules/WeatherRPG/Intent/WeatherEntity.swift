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
            let url = URL.cachesDirectory.appending(component: "\(item.name).pdf")

            let renderer = ImageRenderer(content: VStack {
                Text(item.name)
                Text(item.description)
            }.frame(width: 600))

            var didWritePdf = false
            renderer.render { size, renderer in
                var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)

                guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
                    return
                }
                pdf.beginPDFPage(nil)
                renderer(pdf)
                pdf.endPDFPage()
                pdf.closePDF()
                didWritePdf = true
            }

            guard didWritePdf else {
                throw WeatherEntityPdfRenderingError()
            }
            return .init(url)
        }

        DataRepresentation(exportedContentType: .plainText) {
            let nameLabel = String(localized: "Name", bundle: .module)
            let descriptionLabel = String(localized: "Description", bundle: .module)
            return Data(
                """
                \(nameLabel): \($0.name)
                \(descriptionLabel): \($0.description)
                """.utf8
            )
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
