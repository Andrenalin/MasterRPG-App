// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    static func convert(old: AudioModel) -> ItemDataCodableModel {
        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .audio, collection: .playlist)
        return ItemDataCodableModel(
            id: old.id,
            module: .audio,
            name: old.name,
            information: old.description,
            category: category,
            tags: tags,
            fileUrl: old.fileUrl.wrappedValue,
            displayState: old.displayState,
            parentId: nil,
            entries: old.entries.wrappedValue.enumerated().map { (index, element) in
                EntryDataCodableModel(id: element.id,  index: index, parentId: old.id, childId: element.audioId)
            },
            externalData: nil
        )
    }
}
