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

    var root: DiceRootModel
    var model: DiceModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: DiceRootModel, model: DiceModel) {
        self.root = root
        self.model = model
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

#if compiler(>=6.4)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            attributes.relatedAppEntityIdentifier = EntityIdentifier(for: self)
        }
#endif
        
        return attributes
    }
}

extension DiceEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) {
            Data(
                """
                Name: \($0.name)
                Description: \($0.description)
                """.utf8
            )
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
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3. Dice is one
// of the two modules that needs real overrides: `suggestedEntities()` keeps
// its own 60s result cache (a protocol *requirement*'s own witness always
// wins over `ItemEntityQuery`'s extension default, so this override is
// still honored from every call site, including `entities(matching:)`'s
// empty-string fallback below), and `matches(model:text:)` widens the
// shared name/description predicate to also search tags.
@MainActor
struct DiceEntityQuery: ItemEntityQuery {
    typealias Entity = DiceEntity
    @Dependency var root: DiceRootModel

    // iOS 18+: Cache for better performance
    private static var cachedEntities: [DiceEntity] = []
    private static var lastCacheUpdate: Date = .distantPast
    private static let cacheValidityDuration: TimeInterval = 60 // 1 minute

    func makeEntity(root: DiceRootModel, model: DiceModel) -> DiceEntity { DiceEntity(root: root, model: model) }
    func allIds(root: DiceRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: DiceRootModel, id: UUID) -> DiceModel? { root.itemController.itemSync(for: id) }

    func matches(model: DiceModel, text: String) -> Bool {
        model.name.localizedStandardContains(text) ||
            model.description.localizedStandardContains(text) ||
            model.tags.contains(where: { $0.localizedStandardContains(text) })
    }

    func suggestedEntities() async throws -> [DiceEntity] {
        // Return cached entities if still valid
        if Date().timeIntervalSince(Self.lastCacheUpdate) < Self.cacheValidityDuration {
            return Self.cachedEntities
        }

        // Fetch fresh entities
        var entities: [DiceEntity] = []
        for id in allIds(root: root).prefix(Self.suggestedLimit) {
            guard let model = model(root: root, id: id) else { continue }
            entities.append(makeEntity(root: root, model: model))
        }

        // Update cache
        Self.cachedEntities = entities
        Self.lastCacheUpdate = Date()

        return entities
    }

    // iOS 18+: Invalidate cache when data changes. Called from ItemController
    // whenever a dice set is added, renamed, or deleted, so Siri/Shortcuts/Spotlight
    // suggestions never serve stale entities for the full 60s TTL. See CODE_AUDIT §5.2.
    static func invalidateCache() {
        cachedEntities = []
        lastCacheUpdate = .distantPast
    }
}

#if compiler(>=6.4)
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

extension DiceEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "dice"))
    }
}

#endif
