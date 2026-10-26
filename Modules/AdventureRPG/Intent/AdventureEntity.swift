// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

public struct AdventureEntity: IndexedEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Adventure"),
            numericFormat: "\(placeholder: .int) Adventure"
        )
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    public static let defaultQuery = AdventureEntityQuery()

    public let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    public var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    public var description: String { storedDescription }

    /// The tags of the item, for Shortcuts and the Find action. See CODE_AUDIT_AppIntents §4.5.
    @ComputedProperty
    public var tags: [String] { storedTags }

    @ComputedProperty
    public var isFolder: Bool { storedIsFolder }

    /// A bounded excerpt of the entries' text, indexed so Spotlight matches words from the body.
    @ComputedProperty(indexingKey: \.textContent)
    public var content: String { storedTextContent }

    public let icon: String
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
    init(root: AdventureRootModel, model: AdventureModel) {
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


extension AdventureEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
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
public struct AdventureEntityQuery: @preconcurrency ItemEntityQuery {
    public typealias Entity = AdventureEntity
    @Dependency public var root: AdventureRootModel

    nonisolated public init() {}

    public func makeEntity(root: AdventureRootModel, model: AdventureModel) -> AdventureEntity {
        AdventureEntity(root: root, model: model)
    }
    public func allIds(root: AdventureRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    public func model(root: AdventureRootModel, id: UUID) -> AdventureModel? { root.itemController.itemSync(for: id) }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AdventureEntity: SyncableEntity {}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AdventureEntityQuery: @preconcurrency IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [AdventureEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let all = try await allEntities()
        try await CSSearchableIndex.default().indexAppEntities(all)
    }
}

// MARK: - Find action

/// The properties of the Find action in Shortcuts (name, description, tag, folder), with sorting
/// by name. See CODE_AUDIT_AppIntents §4.5.
extension AdventureEntityQuery: EntityPropertyQuery {
    public typealias ComparatorMappingType = Predicate<AdventureEntity>

    public nonisolated(unsafe) static let properties = QueryProperties {
        Property(\AdventureEntity.$name) {
            ContainsComparator { searchValue in
                #Predicate<AdventureEntity> { $0.name.localizedStandardContains(searchValue) }
            }
            EqualToComparator { searchValue in
                #Predicate<AdventureEntity> { $0.name == searchValue }
            }
        }
        Property(\AdventureEntity.$description) {
            ContainsComparator { searchValue in
                #Predicate<AdventureEntity> { $0.description.localizedStandardContains(searchValue) }
            }
        }
        Property(\AdventureEntity.$tags) {
            ContainsComparator { searchValue in
                #Predicate<AdventureEntity> { entity in entity.tags.contains { tag in tag.localizedStandardContains(searchValue) } }
            }
        }
        Property(\AdventureEntity.$isFolder) {
            EqualToComparator { searchValue in
                #Predicate<AdventureEntity> { $0.isFolder == searchValue }
            }
        }
    }

    public nonisolated(unsafe) static let sortingOptions = SortingOptions {
        SortableBy(\AdventureEntity.$name)
    }

    public nonisolated static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Find adventures by name, description or tag.",
            searchKeywords: ["adventure", "story"],
            resultValueName: "Adventures"
        )
    }

    public nonisolated func entities(
        matching comparators: [Predicate<AdventureEntity>],
        mode: ComparatorMode,
        sortedBy: [EntityQuerySort<AdventureEntity>],
        limit: Int?
    ) async throws -> [AdventureEntity] {
        let nameAscending = sortedBy.first { $0.by == \AdventureEntity.$name }.map { $0.order == .ascending }
        return try await findEntities(
            matching: comparators,
            mode: mode,
            nameAscending: nameAscending,
            name: { $0.name },
            limit: limit
        )
    }
}

#endif
