// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI
import PDFKit

struct TableEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Table"),
            numericFormat: "\(placeholder: .int) Table"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = TableEntityQuery()

    var id: UUID { model.id }

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { model.name }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { model.description }

    var icon: String {
        model.specialCategory ? model.category.icon : root.config.module.icon
    }

    var root: TableRootModel
    var model: TableModel
    
    init(root: TableRootModel, model: TableModel) {
        self.root = root
        self.model = model
    }
}

extension TableEntity: Transferable {
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
struct TableEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    @Dependency var root: TableRootModel

    func suggestedEntities() async throws -> [TableEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [TableEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = TableEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(for identifiers: [TableEntity.ID]) async throws -> [TableEntity] {
        var results: [TableEntity] = []
        for id in identifiers {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            let entity = TableEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func entities(matching: String) async throws -> [TableEntity] {
        let ids = root.itemController.itemDataModel.items
        var results: [TableEntity] = []
        for id in ids {
            guard let model = root.itemController.itemSync(for: id) else { continue }
            guard model.name.contains(matching) || model.description.contains(matching) else { continue }
            let entity = TableEntity(root: root, model: model)
            results.append(entity)
        }
        return results
    }

    func allEntities() async throws -> [TableEntity] {
        try await suggestedEntities()
    }
}

extension TableEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "tablecells.fill"))
    }
}

#endif
