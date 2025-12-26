// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct MapEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Map"),
            numericFormat: "\(placeholder: .int) Map"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = MapEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.description }

    var icon: String {
        model.specialCategory ? model.category.icon : root.config.module.icon
    }

    var root: MapRootModel
    var model: MapModel
    
    init(root: MapRootModel, model: MapModel) {
        self.root = root
        self.model = model
    }
}

extension MapEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            let url = URL.documentsDirectory.appending(path: "\(item.name).pdf")

            let renderer = ImageRenderer(content: VStack {
//                Image(landmark.landmark.backgroundImageName)
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
                Text(item.name)
                Text(item.description)
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
struct MapEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: MapRootModel

    func suggestedEntities() async throws -> [MapEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [MapEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = MapEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [MapEntity.ID]) async throws -> [MapEntity] {
        var results: [MapEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = MapEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [MapEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [MapEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.contains(matching) || model.description.contains(matching) else { continue }
            let entity = MapEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [MapEntity] {
        try await suggestedEntities()
    }
}

extension MapEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "map"))
    }
}

#endif
