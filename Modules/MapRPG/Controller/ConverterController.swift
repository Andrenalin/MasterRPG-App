// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGMaps
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGMaps.MapModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)

        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }

            let entries = item.entries.enumerated().map { (index, entry) in
                MapEntryDataModel(
                    itemId: item.id,
                    entryId: entry.id,
                    index: index,
                    name: entry.name,
                    content: entry.content,
                    coordinates: entry.coordinates,
                    isHexGrid: entry.isHexGrid,
                    isShown: entry.isShown,
                    focused: entry.focused
                )
            }
            entries.forEach { modelContext.insert($0) }

            let character = MapRPG.MapDataModel(
                itemId: item.id,
                photoId: item.photoId,
                width: item.width,
                height: item.height,
                entries: entries,
                pinScale: item.pinScale,
                hexMapScale: item.hexMapScale,
                scale: item.scale
            )
            modelContext.insert(character)
            
            modelContext.insert(
                ItemDataModel(
                    id: item.id,
                    module: .value,
                    name: item.name,
                    information: item.description,
                    category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .character,
                    tags: item.tags,
                    url: nil,
                    displayState: item.displayState
                )
            )
        }
        
        try? modelContext.save()
    }
    
    static func convert(old: MapRPG.MapModel) -> ItemDataCodableModel {
        let entries = old.entries.wrappedValue.enumerated().map { (index, entry) in
            MapEntryDataModel.MapEntryDataModelCodable(
                itemId: old.id,
                entryId: entry.id,
                index: index,
                name: entry.name,
                content: entry.content,
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
        
        return ItemDataCodableModel(
            id: old.id,
            module: .value,
            name: old.name,
            information: old.description,
            category: old.category.wrappedValue,
            tags: old.tags.wrappedValue,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: nil,
            entries: [],
            externalData: externalData
        )
    }
}
