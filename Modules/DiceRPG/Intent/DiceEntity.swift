// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct DiceEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Dice"),
            numericFormat: "\(placeholder: .int) Dice"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(description)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = DiceEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String
    private let storedTags: [String]
    private let storedFirstDieMax: Int?

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // The live model is deliberately not stored: re-resolve it through the root when needed.
    // See CODE_AUDIT_AppIntents §3.1.
    @MainActor
    init(root: DiceRootModel, model: DiceModel) {
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        self.storedTags = model.tags
        self.storedFirstDieMax = model.dice.first.map { Int($0.die.max) }
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
    
    // MARK: - Spotlight Integration (iOS 18+)
    
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.contentDescription = description
        attributes.keywords = ["dice", "roll", name] + storedTags
        attributes.contentType = "Dice"
        attributes.contentTypeTree = ["Dice", "Game", "RPG"]
        
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
        DataRepresentation(exportedContentType: .plainText) {
            EntitySummaryExport.plainText(name: $0.name, description: $0.description)
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
    func allIds(root: DiceRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: DiceRootModel, id: UUID) -> DiceModel? { root.itemController.itemSync(for: id) }

    func matches(model: DiceModel, text: String) -> Bool {
        model.name.localizedStandardContains(text) ||
            model.description.localizedStandardContains(text) ||
            model.tags.contains(where: { $0.localizedStandardContains(text) })
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension DiceEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension DiceEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [DiceEntity.ID],
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
