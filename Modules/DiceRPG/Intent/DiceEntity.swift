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
            """
            Name: \($0.name)
            Description: \($0.description)
            """.data(using: .utf8)!
        }
    }
}

extension DiceEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://DICE/0/\(.id)"
    }
}

@MainActor
struct DiceEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: DiceRootModel
    
    // iOS 18+: Cache for better performance
    private static var cachedEntities: [DiceEntity] = []
    private static var lastCacheUpdate: Date = .distantPast
    private static let cacheValidityDuration: TimeInterval = 60 // 1 minute

    func suggestedEntities() async throws -> [DiceEntity] {
        // Return cached entities if still valid
        if Date().timeIntervalSince(Self.lastCacheUpdate) < Self.cacheValidityDuration {
            return Self.cachedEntities
        }
        
        // Fetch fresh entities
        let entities = await fetchEntities()
        
        // Update cache
        Self.cachedEntities = entities
        Self.lastCacheUpdate = Date()
        
        return entities
    }
    
    private func fetchEntities() async -> [DiceEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [DiceEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = DiceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [DiceEntity.ID]) async throws -> [DiceEntity] {
        var results: [DiceEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = DiceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching string: String) async throws -> [DiceEntity] {
        let allEntities = try await suggestedEntities()
        return allEntities.filter { entity in
            entity.name.localizedStandardContains(string) ||
            entity.description.localizedStandardContains(string) ||
            entity.model.tags.contains(where: { $0.localizedStandardContains(string) })
        }
    }

    func allEntities() async throws -> [DiceEntity] {
        try await suggestedEntities()
    }
    
    // iOS 18+: Invalidate cache when data changes
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
