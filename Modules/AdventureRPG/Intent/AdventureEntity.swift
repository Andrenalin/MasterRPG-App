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

    public let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: AdventureRootModel
    var model: AdventureModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: AdventureRootModel, model: AdventureModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

extension AdventureEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            let url = URL.cachesDirectory.appending(component: "\(item.name).pdf")

            let renderer = ImageRenderer(content: VStack {
                Text(verbatim: item.name)
                Text(verbatim: item.description)
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

        DataRepresentation(exportedContentType: .plainText) {
            """
            Name: \($0.name)
            Description: \($0.description)
            """.data(using: .utf8)!
        }
    }
}

public struct AdventureEntityQuery: @preconcurrency EntityQuery, @preconcurrency EntityStringQuery, @preconcurrency EnumerableEntityQuery {
    @Dependency var root: AdventureRootModel
    private static let suggestedEntityLimit = 20
    private static let matchingEntityLimit = 25

    public init() {}

    @MainActor
    public func suggestedEntities() async throws -> [AdventureEntity] {
        let ids = root.itemController.itemDataModel.items.prefix(Self.suggestedEntityLimit)
        var results: [AdventureEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    @MainActor
    public func entities(for identifiers: [AdventureEntity.ID]) async throws -> [AdventureEntity] {
        var results: [AdventureEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    @MainActor
    public func entities(matching: String) async throws -> [AdventureEntity] {
        guard !matching.isEmpty else { return try await suggestedEntities() }
        let ids = root.itemController.itemDataModel.items
        var results: [AdventureEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.localizedStandardContains(matching) || model.description.localizedStandardContains(matching) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
            guard results.count < Self.matchingEntityLimit else { break }
        }
        return results
    }

    @MainActor
    public func allEntities() async throws -> [AdventureEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [AdventureEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension AdventureEntity: SyncableEntity, OwnershipProvidingEntity {
    public var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AdventureEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [AdventureEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let all = try await allEntities()
        try await CSSearchableIndex.default().indexAppEntities(all)
    }
}
#endif

extension AdventureEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "wand.and.stars"))
    }
}

#endif
