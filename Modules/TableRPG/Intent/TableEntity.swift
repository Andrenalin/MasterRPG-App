// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct TableEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Table"),
            numericFormat: "\(placeholder: .int) tables"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = TableEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: TableRootModel
    var model: TableModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: TableRootModel, model: TableModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

extension TableEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            let url = URL.cachesDirectory.appending(component: "\(item.name).pdf")

            let renderer = ImageRenderer(content: VStack {
                Text(item.name)
                Text(item.description)
            }.frame(width: 600))

            renderer.render { size, renderer in
                var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)

                guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
                    return
                }
                pdf.beginPDFPage(nil)
                renderer(pdf)
                pdf.endPDFPage()
                pdf.closePDF()
            }

            return .init(url)
        }

        DataRepresentation(exportedContentType: .plainText) { item in
            String(
                localized: "Name: \(item.name)\nDescription: \(item.description)",
                bundle: .module
            )
            .data(using: .utf8) ?? Data()
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3.
@MainActor
struct TableEntityQuery: ItemEntityQuery {
    typealias Entity = TableEntity
    @Dependency var root: TableRootModel

    func makeEntity(root: TableRootModel, model: TableModel) -> TableEntity { TableEntity(root: root, model: model) }
    func allIds(root: TableRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: TableRootModel, id: UUID) -> TableModel? { root.itemController.itemSync(for: id) }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension TableEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

// @preconcurrency is required, not optional: CoreSpotlight's
// CSSearchableIndexDescription is not Sendable, and this conformance's
// requirements cross into this @MainActor-isolated type — confirmed by
// removing it, which fails with "Non-Sendable parameter type
// 'CSSearchableIndexDescription' cannot be sent... into main actor-isolated
// implementation". See CODE_AUDIT_Table §4.1.
@available(iOS 27, macOS 27, visionOS 27, *)
extension TableEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [TableEntity.ID],
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

extension TableEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "tablecells.fill"))
    }
}

#endif
