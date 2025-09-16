// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    static func convert(old: PdfModel) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            PdfEntryDataModel.PdfEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: entry.content,
                bounds: entry.bounds,
                pageLabel: entry.pageLabel
            )
        }
        let model = PdfDataModel.PdfDataModelCodable(
            itemId: old.id,
            entries: entries
        )
        let externalData = try? JSONEncoder().encode(model)

        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .pdf, collection: .bookshelf)
        return ItemDataCodableModel(
            id: old.id,
            module: .pdf,
            name: old.name,
            information: old.description,
            category: category,
            tags: tags,
            fileUrl: old.fileUrl.wrappedValue,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
}
