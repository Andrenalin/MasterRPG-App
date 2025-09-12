// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController: ConverterControllable {
    @MainActor
    static func convert(old: MapRPG.MapModel, itemController: ItemController) -> ItemDataCodableModel {
        let linkRegisterController = LinkRegisterController(container: itemController.container)
        
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            // Scan and register links in entry name and content
            let updatedContent = scanAndRegisterLinks(in: entry.content, destinationId: old.id, destinationEntryId: entry.id, destinationModule: .map, linkRegisterController: linkRegisterController)
            
            return MapEntryDataModel.MapEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: updatedContent,
                coordinates: entry.coordinates,
                isHexGrid: entry.isHexGrid,
                isShown: entry.isShown,
                focused: entry.focused
            )
        }
        let model = MapDataModel.MapDataModelCodable(
            itemId: old.id,
            photoId: old.photoId.wrappedValue,
            width: old.width,
            height: old.height,
            entries: entries,
            pinScale: old.pinScale,
            hexMapScale: old.hexMapScale.wrappedValue,
            scale: old.scale
        )
        let externalData = try? JSONEncoder().encode(model)
        
        // Register photoId as a link if present
        if let photoId = old.photoId.wrappedValue {
            _ = linkRegisterController.register(sourceId: old.id, sourceModule: .map, destinationId: photoId, destinationModule: .photo)
        }
        
        let (category, tags) = convert(category: old.category.wrappedValue, tags: old.tags.wrappedValue, module: .map, collection: .collection)
        return ItemDataCodableModel(
            id: old.id,
            module: .map,
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
