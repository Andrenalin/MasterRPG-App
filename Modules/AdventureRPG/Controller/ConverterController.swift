// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    @MainActor
    static func convert(old: AdventureRPG.AdventureModel, itemController: ItemController) -> ItemDataCodableModel {
        let linkRegisterController = LinkRegisterController(container: itemController.container)
        
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            // Scan and register links in entry name and content
            let updatedContent = scanAndRegisterLinks(in: entry.content, destinationId: old.id, destinationEntryId: entry.id, destinationModule: .adventure, linkRegisterController: linkRegisterController)
            
            return AdventureEntryDataModel.AdventureEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: updatedContent
            )
        }
        let model = AdventureDataModel.AdventureDataModelCodable(
            itemId: old.id,
            photoId: old.photoId.wrappedValue,
            entries: entries,
        )
        let externalData = try? JSONEncoder().encode(model)
        
        // Register photoId as a link if present
        if let photoId = old.photoId.wrappedValue {
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .adventure, destinationId: photoId, destinationModule: .photo)
        }
        
        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .adventure, collection: .collection)
        return ItemDataCodableModel(
            id: old.id,
            module: .adventure,
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
    private static func scanAndRegisterLinks(in text: String, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules, linkRegisterController: LinkRegisterController) -> String {
        let linkReplaceModels = LinkReplaceController.links(for: text)
        
        var updatedText = text
        
        for link in linkReplaceModels {
            let linkModel = linkRegisterController.register(link: link, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModule: destinationModule)
            let newLinkFormat = linkRegisterController.markDown(for: linkModel)
            updatedText = updatedText.replacingOccurrences(of: link.markDown, with: newLinkFormat)
        }
        
        return updatedText
    }
}
