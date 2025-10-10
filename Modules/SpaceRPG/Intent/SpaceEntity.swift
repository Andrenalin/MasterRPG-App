// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit
import CoreRPG

struct SpaceEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Space"),
            numericFormat: "\(placeholder: .int) 3D objects"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)"
            //,
            //image: .init(data: try! self.thumbnailRepresentationData)
        )
    }

    static let defaultQuery = SpaceEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name.wrappedValue }

    // Maps the description variable to the Spotlight indexing key `contentDescription`.
    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.information.wrappedValue }

    var root: SpaceRootModel
    var model: ItemDataCodableModel
    
    init(root: SpaceRootModel, model: ItemDataCodableModel) {
        self.root = root
        self.model = model
    }
}

extension SpaceEntity: Transferable {
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
            Pdf: \($0.name)
            Description: \($0.description)
            """.data(using: .utf8)!
        }
    }
}

@MainActor
struct SpaceEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: SpaceRootModel

    func suggestedEntities() async throws -> [SpaceEntity] {
        let ids = root.itemController.allItemIds()
        var results: [SpaceEntity] = []
        for id in ids {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            let entity = SpaceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [SpaceEntity.ID]) async throws -> [SpaceEntity] {
        var results: [SpaceEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            let entity = SpaceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [SpaceEntity] {
        let ids = root.itemController.allItemIds()
        var results: [SpaceEntity] = []
        for id in ids {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            guard model.name.wrappedValue.contains(matching) || model.information.wrappedValue.contains(matching) else { continue }
            let entity = SpaceEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [SpaceEntity] {
        try await suggestedEntities()
    }
}

extension SpaceEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "view.3d"))
    }
}

#endif
