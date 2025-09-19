// @copyright André Trettin

import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit
import CoreRPG

struct DiceEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Dice"),
            numericFormat: "\(placeholder: .int) dice"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)"
            //,
            //image: .init(data: try! self.thumbnailRepresentationData)
        )
    }

    static let defaultQuery = DiceEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name.wrappedValue }

    // Maps the description variable to the Spotlight indexing key `contentDescription`.
    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.information.wrappedValue }

    var root: DiceRootModel
    var model: ItemDataCodableModel
    
    init(root: DiceRootModel, model: ItemDataCodableModel) {
        self.root = root
        self.model = model
    }
}

extension DiceEntity: Transferable {
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

        DataRepresentation(exportedContentType: .image) {
            try await $0.imageRepresentationData
        }

        DataRepresentation(exportedContentType: .plainText) {
            """
            Photo: \($0.name)
            Description: \($0.description)
            """.data(using: .utf8)!
        }
    }
}

@MainActor
struct DiceEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: DiceRootModel

    func suggestedEntities() async throws -> [DiceEntity] {
        let ids = root.itemController.allItemIds(module: .dice)
        var results: [DiceEntity] = []
        for id in ids {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            let entity = DiceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [DiceEntity.ID]) async throws -> [DiceEntity] {
        var results: [DiceEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            let entity = DiceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [DiceEntity] {
        let ids = root.itemController.allItemIds(module: .dice)
        var results: [DiceEntity] = []
        for id in ids {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            guard model.name.wrappedValue.contains(matching) || model.information.wrappedValue.contains(matching) else { continue }
            let entity = DiceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [DiceEntity] {
        try await suggestedEntities()
    }
}

extension DiceEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "dice"))
    }
}
