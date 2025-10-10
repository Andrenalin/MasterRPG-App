// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit
import CoreRPG

struct WeatherEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Weather"),
            numericFormat: "\(placeholder: .int) Weather"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)"
            //,
            //image: .init(data: try! self.thumbnailRepresentationData)
        )
    }

    static let defaultQuery = WeatherEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name.wrappedValue }

    // Maps the description variable to the Spotlight indexing key `contentDescription`.
    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.information.wrappedValue }

    var root: WeatherRootModel
    var model: ItemDataCodableModel
    
    init(root: WeatherRootModel, model: ItemDataCodableModel) {
        self.root = root
        self.model = model
    }
}

extension WeatherEntity: Transferable {
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
            Pdf: \($0.name)
            Description: \($0.description)
            """.data(using: .utf8)!
        }
    }
}

@MainActor
struct WeatherEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: WeatherRootModel

    func suggestedEntities() async throws -> [WeatherEntity] {
        let ids = root.itemController.allItemIds()
        var results: [WeatherEntity] = []
        for id in ids {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            let entity = WeatherEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [WeatherEntity.ID]) async throws -> [WeatherEntity] {
        var results: [WeatherEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            let entity = WeatherEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [WeatherEntity] {
        let ids = root.itemController.allItemIds()
        var results: [WeatherEntity] = []
        for id in ids {
            guard let model = root.itemController.itemDataCodableModel(for: id) else { continue }
            guard model.name.wrappedValue.contains(matching) || model.information.wrappedValue.contains(matching) else { continue }
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
