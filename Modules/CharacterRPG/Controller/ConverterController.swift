// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    @MainActor
    static func convert(old: ValueModel, itemController: ItemController) -> ItemDataCodableModel {
        let linkRegisterController = LinkRegisterController(container: itemController.container)
        
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            // Scan and register links in entry name and content
            let updatedName = scanAndRegisterLinks(in: entry.name, destinationId: old.id, destinationEntryId: entry.id, destinationModule: .value, linkRegisterController: linkRegisterController)
            let updatedContent = scanAndRegisterLinks(in: entry.value, destinationId: old.id, destinationEntryId: entry.id, destinationModule: .value, linkRegisterController: linkRegisterController)
            
            // Register entry dice if present
            if let diceId = entry.diceId {
                _ = linkRegisterController.register(sourceId: old.id, sourceEntryId: entry.id, sourceModule: .value, destinationId: diceId, destinationModule: .dice)
            }
            
            // Register entry valueId if present
            if let valueId = entry.valueId {
                _ = linkRegisterController.register(sourceId: old.id, sourceEntryId: entry.id, sourceModule: .value, destinationId: valueId, destinationModule: .value)
            }
            
            return CharacterEntryDataModel.Value(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: updatedName,
                content: updatedContent,
                valueType: entry.type,
                diceId: entry.diceId,
                valueId: entry.valueId
            )
        }
        let model = CharacterDataModel.Value(
            itemId: old.id,
            diceId: entries.first { $0.diceId != nil }?.diceId,
            photoId: old.photoId.wrappedValue,
            photos: old.photos.wrappedValue,
            parentId: old.parentId,
            entries: entries
        )
        let externalData = try? JSONEncoder().encode(model)
        
        // Register main model photoId if present
        if let photoId = old.photoId.wrappedValue {
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .value, destinationId: photoId, destinationModule: .photo)
        }
        
        // Register photos array
        old.photos.wrappedValue.forEach { photoId in
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .value, destinationId: photoId, destinationModule: .photo)
        }
        
        // Register main model diceId if present (from first entry that has one)
        if let diceId = entries.first(where: { $0.diceId != nil })?.diceId {
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .value, destinationId: diceId, destinationModule: .dice)
        }
        
        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .value, collection: .collection)
        return ItemDataCodableModel(
            id: old.id,
            module: .value,
            name: old.name,
            information: old.description,
            category: category,
            tags: tags,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: old.parentId,
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
