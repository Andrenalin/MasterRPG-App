// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    static func convert(old: PhotoModel) -> ItemDataCodableModel {
        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .photo, collection: .album)
        return ItemDataCodableModel(
            id: old.id,
            module: .photo,
            name: old.name,
            information: old.description,
            category: category,
            tags: tags,
            fileUrl: old.fileUrl.wrappedValue,
            displayState: old.displayState,
            parentId: nil,
            entries: old.entries.wrappedValue.enumerated().map { (index, element) in
                EntryDataCodableModel(id: element.id,  index: index, parentId: old.id, childId: element.photoId)
            },
            externalData: nil
        )
    }
}
