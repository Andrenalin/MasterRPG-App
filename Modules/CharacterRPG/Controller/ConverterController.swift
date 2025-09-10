// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

public struct ConverterController {
//    public static func insert(items: [RPGValues.ValueModel], into modelContext: ModelContext) {
//        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
//        let models = try? modelContext.fetch(fetchDesc)
//
//        items.forEach { item in
//            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
//            
//            let character = CharacterRPG.CharacterDataModel(itemId: item.id, photoId: item.photoId, photos: item.photos, parentId: item.parentId)
//            modelContext.insert(character)
//            let entries = item.entries.enumerated().map { (index, entry) in
//                CharacterEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.value, valueType: toCharacterValueType(entry.type), diceId: entry.diceId, valueId: entry.valueId)
//            }
//            entries.forEach { modelContext.insert($0) }
//            
//            modelContext.insert(
//                ItemDataModel(id: item.id, module: .value, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .character, tags: item.tags, url: nil, displayState: item.displayState)
//            )
//        }
//        
//        try? modelContext.save()
//    }
//    
//    static func toCharacterValueType(_ value: RPGValues.ValueEntryModel.ValueType) -> CharacterRPG.CharacterEntryDataModel.ValueType {
//        CharacterRPG.CharacterEntryDataModel.ValueType(rawValue: value.rawValue) ?? .text
//    }

    @MainActor
    static func convert(old: CharacterRPG.ValueModel, itemController: ItemController) -> ItemDataCodableModel {
        let linkRegisterController = LinkRegisterController(itemController: itemController, module: .value)
        
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
            
            return CharacterEntryDataModel.CharacterEntryDataModelCodable(
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
        let model = CharacterDataModel.CharacterDataModelCodable(
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
        
        return ItemDataCodableModel(
            id: old.id,
            module: .value,
            name: old.name,
            information: old.description,
            category: old.category.wrappedValue,
            tags: old.tags.wrappedValue,
            fileUrl: nil,
            displayState: old.displayState,
            parentId: old.parentId,
            entries: [],
            externalData: externalData
        )
    }
    
    @MainActor
    private static func scanAndRegisterLinks(in text: String, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: CoreRPG.NetworkModules, linkRegisterController: LinkRegisterController) -> String {
        let linkReplaceModels = CoreRPG.LinkReplaceController.links(for: text)
        
        var updatedText = text
        
        for link in linkReplaceModels {
            let linkId = linkRegisterController.register(link: link, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModule: destinationModule)
            let newLinkFormat = "[\(link.name)](RPG://\(linkId.uuidString))"
            updatedText = updatedText.replacingOccurrences(of: link.markDown, with: newLinkFormat)
        }
        
        return updatedText
    }
}
