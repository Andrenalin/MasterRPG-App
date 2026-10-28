// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI

struct DiceEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Dice"),
            numericFormat: "\(placeholder: .int) Dice",
            synonyms: ["Dice set", "Die"]
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = DiceEntityQuery()

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
    private let storedIsFolder: Bool
    private let storedTextContent: String
    private let storedTags: [String]
    private let storedFirstDieMax: Int?

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // The live model is deliberately not stored: re-resolve it through the root when needed.
    // See CODE_AUDIT_AppIntents §3.1.
    /// `includingText: false` leaves out the excerpt and subtitle, for the Find action's matching
    /// (`makeFindEntity`).
    @MainActor
    init(root: DiceRootModel, model: DiceModel, includingText: Bool = true) {
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        self.storedIsFolder = model.category == .folder
        self.storedTextContent = includingText ? IntentEntityText.excerpt(of: model) : ""
        self.subtitle = includingText ? IntentEntityText.subtitle(of: model) { root.itemController.itemSync(for: $0) } : ""
        self.storedTags = model.tags
        self.storedFirstDieMax = model.dice.first.map { Int($0.die.max) }
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
    
    // MARK: - Spotlight Integration (iOS 18+)
    
    /// Starts from the system's default set, which carries the `@ComputedProperty(indexingKey:)`
    /// fields, and only adds what is specific to dice. The earlier set was built from scratch and
    /// gave `contentType` and `contentTypeTree` values that are not UTIs, which Spotlight ignores.
    /// See CODE_AUDIT_AppIntents §5.5.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.keywords = ["dice", "roll", name] + storedTags

        // Add dice-specific metadata
        if let firstDieMax = storedFirstDieMax {
            attributes.comment = "D\(firstDieMax)"
        }

        if #available(iOS 27, macOS 27, visionOS 27, *) {
            attributes.relatedAppEntityIdentifier = EntityIdentifier(for: self)
        }

        return attributes
    }
}

extension DiceEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { @MainActor item in
            EntitySummaryExport.plainText(id: item.id, module: .dice, name: item.name, description: item.description)
        }
    }
}

extension DiceEntity: URLRepresentableEntity {
    // Cannot compose this from `URL.appScheme`/`NetworkModules.dice.token` as CODE_AUDIT §9.13
    // suggested: `URLRepresentation`'s string-interpolation literal is a compile-time template
    // (its `StringInterpolation.Token` only accepts KeyPath-based placeholders like `.id`, which
    // the framework resolves per-entity later) — it does not support interpolating an arbitrary
    // runtime `String` value the way a normal Swift string does. Confirmed by trying it: the
    // build fails with "cannot convert value of type 'String' to expected argument type
    // 'EntityURLRepresentation<DiceEntity>.StringInterpolation.Token'". The literal below must
    // stay hand-kept in sync with `URL.appScheme` ("RPG") and `NetworkModules.dice.token`
    // ("DICE") — verified in `DiceEntityURLRepresentationTests`.
    static var urlRepresentation: URLRepresentation {
        "RPG://DICE/0/\(.id)"
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3. Dice widens the
// shared name/description predicate to also search tags.
//
// The former 60 s `suggestedEntities()` result cache was removed: nothing ever
// invalidated it, so Siri/Shortcuts/Spotlight served stale (or, on a cold launch,
// empty) dice for the whole TTL, and it skipped the shared trashed-item filter.
// Building the suggestions from the in-memory models is cheap. See CODE_AUDIT_18
// §5.10 and §3.2.
@MainActor
struct DiceEntityQuery: ItemEntityQuery {
    typealias Entity = DiceEntity
    @Dependency var root: DiceRootModel

    func makeEntity(root: DiceRootModel, model: DiceModel) -> DiceEntity { DiceEntity(root: root, model: model) }
    func makeFindEntity(root: DiceRootModel, model: DiceModel) -> DiceEntity { DiceEntity(root: root, model: model, includingText: false) }
    func allIds(root: DiceRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: DiceRootModel, id: UUID) -> DiceModel? { root.itemController.itemSync(for: id) }

    func matches(model: DiceModel, text: String) -> Bool {
        model.name.localizedStandardContains(text) ||
            model.description.localizedStandardContains(text) ||
            model.tags.contains(where: { $0.localizedStandardContains(text) })
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension DiceEntity: SyncableEntity {}

@available(iOS 27, macOS 27, visionOS 27, *)
extension DiceEntityQuery: @preconcurrency IndexedEntityQuery {}

// MARK: - Find action

/// The properties of the Find action in Shortcuts (name, description, tag, folder), with sorting
/// by name. See CODE_AUDIT_AppIntents §4.5.
extension DiceEntityQuery: EntityPropertyQuery {
    typealias ComparatorMappingType = Predicate<DiceEntity>

    nonisolated(unsafe) static let properties = QueryProperties {
        Property(\DiceEntity.$name) {
            ContainsComparator { searchValue in
                #Predicate<DiceEntity> { $0.name.localizedStandardContains(searchValue) }
            }
            EqualToComparator { searchValue in
                #Predicate<DiceEntity> { $0.name == searchValue }
            }
        }
        Property(\DiceEntity.$description) {
            ContainsComparator { searchValue in
                #Predicate<DiceEntity> { $0.description.localizedStandardContains(searchValue) }
            }
        }
        Property(\DiceEntity.$tags) {
            ContainsComparator { searchValue in
                #Predicate<DiceEntity> { entity in entity.tags.contains { tag in tag.localizedStandardContains(searchValue) } }
            }
        }
        Property(\DiceEntity.$isFolder) {
            EqualToComparator { searchValue in
                #Predicate<DiceEntity> { $0.isFolder == searchValue }
            }
        }
    }

    nonisolated(unsafe) static let sortingOptions = SortingOptions {
        SortableBy(\DiceEntity.$name)
    }

    nonisolated static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Find dice sets by name, description or tag.",
            searchKeywords: ["dice", "roll"],
            resultValueName: "Dice"
        )
    }

    nonisolated func entities(
        matching comparators: [Predicate<DiceEntity>],
        mode: ComparatorMode,
        sortedBy: [EntityQuerySort<DiceEntity>],
        limit: Int?
    ) async throws -> [DiceEntity] {
        let nameAscending = sortedBy.first { $0.by == \DiceEntity.$name }.map { $0.order == .ascending }
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
