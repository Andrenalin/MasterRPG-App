// @copyright André Trettin

import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct AudioEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Audio"),
            numericFormat: "\(placeholder: .int) audios"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)"
            //,
            //image: .init(data: try! self.thumbnailRepresentationData)
        )
    }

    static let defaultQuery = PhotoEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    // Maps the description variable to the Spotlight indexing key `contentDescription`.
    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.information }

    var root: AudioRootModel
    var model: AudioModel
    
    init(root: AudioRootModel, model: AudioModel) {
        self.root = root
        self.model = model
    }
}

extension AudioEntity: Transferable {
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
struct PhotoEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: AudioRootModel

    func suggestedEntities() async throws -> [AudioEntity] {
        let ids = root.itemController.allItemIds()
        var results: [AudioEntity] = []
        for id in ids {
            guard let model = await root.itemController.item(for: id) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [AudioEntity.ID]) async throws -> [AudioEntity] {
        var results: [AudioEntity] = []
        for id in identifiers {
            guard let model = await root.itemController.item(for: id) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [AudioEntity] {
        let ids = root.itemController.allItemIds()
        var results: [AudioEntity] = []
        for id in ids {
            guard let model = await root.itemController.item(for: id) else { continue }
            guard model.name.contains(matching) || model.information.contains(matching) else { continue }
            let entity = AudioEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [AudioEntity] {
        try await suggestedEntities()
    }
}

extension AudioEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "photo"))
    }
}
