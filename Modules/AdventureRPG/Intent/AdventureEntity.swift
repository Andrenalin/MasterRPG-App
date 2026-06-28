// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct AdventureEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Adventure"),
            numericFormat: "\(placeholder: .int) Adventure"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = AdventureEntityQuery()

    var id: UUID { model.id }


    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.description }

    var icon: String {
        model.specialCategory ? model.category.icon : root.config.module.icon
    }

    var root: AdventureRootModel
    var model: AdventureModel
    
    init(root: AdventureRootModel, model: AdventureModel) {
        self.root = root
        self.model = model
    }
}

extension AdventureEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { @MainActor landmark in
            let url = URL.documentsDirectory.appending(path: "\(landmark.name).pdf")

            let renderer = ImageRenderer(content: VStack {
//                Image(landmark.landmark.backgroundImageName)
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
                Text(landmark.name)
                Text(landmark.description)
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

@MainActor
struct AdventureEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: AdventureRootModel

    func suggestedEntities() async throws -> [AdventureEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [AdventureEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [AdventureEntity.ID]) async throws -> [AdventureEntity] {
        var results: [AdventureEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [AdventureEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [AdventureEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.localizedStandardContains(matching) || model.description.localizedStandardContains(matching) else { continue }
            let entity = AdventureEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [AdventureEntity] {
        try await suggestedEntities()
    }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AdventureEntity: SyncableEntity {}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AdventureEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [AdventureEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    @available(iOS 27, macOS 27, visionOS 27, *)
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let all = try await allEntities()
        try await CSSearchableIndex.default().indexAppEntities(all)
    }
}

extension AdventureEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "wand.and.stars"))
    }
}

#endif
