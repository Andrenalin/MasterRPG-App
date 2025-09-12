// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    @MainActor
    static func convert(old: TableModel, itemController: ItemController) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            let updatedContent = scanAndRegisterLinks(in: entry.content, destinationId: old.id, destinationEntryId: entry.id, destinationModule: CoreRPG.NetworkModules.table, itemController: itemController)
            return TableEntryDataModel.TableEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: updatedContent
            )
        }
        let model = TableDataModel.TableDataModelCodable(
            itemId: old.id,
            diceId: old.diceId.wrappedValue,
            entries: entries
        )
        let externalData = try? JSONEncoder().encode(model)
        
        // Register diceId as a link if present
        if let diceId = old.diceId.wrappedValue {
            let linkRegisterController = LinkRegisterController(container: itemController.container)
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .table, destinationId: diceId, destinationModule: .dice)
        }
        
        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .table, collection: .collection)
        return ItemDataCodableModel(
            id: old.id,
            module: .table,
            name: old.name,
            information: old.description,
            category: category,
            tags: tags,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
    
    @MainActor
    static func scanAndRegisterLinks(in text: String, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules, itemController: ItemController) -> String {
        let linkReplaceModels = LinkReplaceController.links(for: text)
        let linkRegisterController = LinkRegisterController(container: itemController.container)
        
        var updatedText = text
        
        for link in linkReplaceModels {
            let linkModel = linkRegisterController.register(link: link, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModule: destinationModule)
            let newLinkFormat = linkRegisterController.markDown(for: linkModel)
            updatedText = updatedText.replacingOccurrences(of: link.markDown, with: newLinkFormat)
        }
        
        return updatedText
    }
}
