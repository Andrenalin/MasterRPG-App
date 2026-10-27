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
            numericFormat: "\(placeholder: .int) tables",
            synonyms: ["Random table"]
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = TableEntityQuery()

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

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // The live model is deliberately not stored: re-resolve it through the root when needed.
    // See CODE_AUDIT_AppIntents §3.1.
    @MainActor
    init(root: TableRootModel, model: TableModel) {
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

/// The link the app already opens (`RPG://TABLES/0/<id>`), so a tapped Spotlight result opens the
/// item on every OS version. The literal must match `URL.appScheme` and
/// `NetworkModules.table.token`; see `EntityUrlRepresentationTests`.
/// See CODE_AUDIT_AppIntents2 §4.1.
extension TableEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://TABLES/0/\(.id)"
    }
}

extension TableEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { @MainActor item in
            EntitySummaryExport.plainText(id: item.id, module: .table, name: item.name, description: item.description)
        }

        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            .init(try EntitySummaryExport.pdf(id: item.id, module: .table, name: item.name, description: item.description))
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
extension TableEntity: SyncableEntity {}

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

#endif
