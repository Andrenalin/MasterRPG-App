// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct WeatherEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Weather"),
            numericFormat: "\(placeholder: .int) Weather"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = WeatherEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.description }

    var icon: String {
        model.specialCategory ? model.category.icon : root.config.module.icon
    }
    
    var root: WeatherRootModel
    var model: WeatherModel
    
    init(root: WeatherRootModel, model: WeatherModel) {
        self.root = root
        self.model = model
    }
}

extension WeatherEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { @MainActor item in
            let url = URL.documentsDirectory.appending(path: "\(item.name).pdf")

            let renderer = ImageRenderer(content: VStack {
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
struct WeatherEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: WeatherRootModel

    func suggestedEntities() async throws -> [WeatherEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [WeatherEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = WeatherEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [WeatherEntity.ID]) async throws -> [WeatherEntity] {
        var results: [WeatherEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = WeatherEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [WeatherEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [WeatherEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.contains(matching) || model.description.contains(matching) else { continue }
            let entity = WeatherEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [WeatherEntity] {
        try await suggestedEntities()
    }
}

extension WeatherEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "cloud.bolt.rain"))
    }
}

#endif
