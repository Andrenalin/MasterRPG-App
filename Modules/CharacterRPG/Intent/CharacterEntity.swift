// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI

struct CharacterEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Character"),
            numericFormat: "\(placeholder: .int) Character",
            synonyms: ["Player", "NPC", "Monster"]
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = CharacterEntityQuery()

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
    /// `includingText: false` leaves out the excerpt and subtitle, for the Find action's matching
    /// (`makeFindEntity`).
    @MainActor
    init(root: CharacterRootModel, model: ValueModel, includingText: Bool = true) {
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        self.storedTags = model.tags
        self.storedIsFolder = model.category == .folder
        self.storedTextContent = includingText
            ? IntentEntityText.excerpt(of: model) { root.linkController.calculate(entry: $0) ?? $0.content }
            : ""
        self.subtitle = includingText ? IntentEntityText.subtitle(of: model) { root.itemController.itemSync(for: $0) } : ""
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// The link the app already opens (`RPG://VALUES/0/<id>`), so a tapped Spotlight result opens the
/// item on every OS version. The literal must match `URL.appScheme` and
/// `NetworkModules.value.token`; see `EntityUrlRepresentationTests`.
/// See CODE_AUDIT_AppIntents2 §4.1.
extension CharacterEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://VALUES/0/\(.id)"
    }
}

extension CharacterEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { @MainActor item in
            EntitySummaryExport.plainText(id: item.id, module: .value, name: item.name, description: item.description)
        }

        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            .init(try await EntitySummaryExport.pdf(id: item.id, module: .value, name: item.name, description: item.description))
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3.
@MainActor
struct CharacterEntityQuery: ItemEntityQuery {
    typealias Entity = CharacterEntity
    @Dependency var root: CharacterRootModel

    func makeEntity(root: CharacterRootModel, model: ValueModel) -> CharacterEntity { CharacterEntity(root: root, model: model) }
    func makeFindEntity(root: CharacterRootModel, model: ValueModel) -> CharacterEntity { CharacterEntity(root: root, model: model, includingText: false) }
    func allIds(root: CharacterRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: CharacterRootModel, id: UUID) -> ValueModel? { root.itemController.itemSync(for: id) }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension CharacterEntity: SyncableEntity {}

@available(iOS 27, macOS 27, visionOS 27, *)
extension CharacterEntityQuery: @preconcurrency IndexedEntityQuery {}

// MARK: - Find action

/// The properties of the Find action in Shortcuts (name, description, tag, folder), with sorting
/// by name. See CODE_AUDIT_AppIntents §4.5.
extension CharacterEntityQuery: EntityPropertyQuery {
    typealias ComparatorMappingType = Predicate<CharacterEntity>

    nonisolated(unsafe) static let properties = QueryProperties {
        Property(\CharacterEntity.$name) {
            ContainsComparator { searchValue in
                #Predicate<CharacterEntity> { $0.name.localizedStandardContains(searchValue) }
            }
            EqualToComparator { searchValue in
                #Predicate<CharacterEntity> { $0.name == searchValue }
            }
        }
        Property(\CharacterEntity.$description) {
            ContainsComparator { searchValue in
                #Predicate<CharacterEntity> { $0.description.localizedStandardContains(searchValue) }
            }
        }
        Property(\CharacterEntity.$tags) {
            ContainsComparator { searchValue in
                #Predicate<CharacterEntity> { entity in entity.tags.contains { tag in tag.localizedStandardContains(searchValue) } }
            }
        }
        Property(\CharacterEntity.$isFolder) {
            EqualToComparator { searchValue in
                #Predicate<CharacterEntity> { $0.isFolder == searchValue }
            }
        }
    }

    nonisolated(unsafe) static let sortingOptions = SortingOptions {
        SortableBy(\CharacterEntity.$name)
    }

    nonisolated static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Find characters by name, description or tag.",
            searchKeywords: ["character", "npc", "monster"],
            resultValueName: "Characters"
        )
    }

    nonisolated func entities(
        matching comparators: [Predicate<CharacterEntity>],
        mode: ComparatorMode,
        sortedBy: [EntityQuerySort<CharacterEntity>],
        limit: Int?
    ) async throws -> [CharacterEntity] {
        let nameAscending = sortedBy.first { $0.by == \CharacterEntity.$name }.map { $0.order == .ascending }
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
