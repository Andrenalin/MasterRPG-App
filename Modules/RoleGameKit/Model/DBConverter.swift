// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation

import AdventureRPG
import AudioRPG
import CharacterRPG
@testable import DiceRPG
import MapRPG
@testable import PdfRPG
@testable import PhotoRPG
import SpaceRPG
@testable import TableRPG
@testable import WeatherRPG

import RPGAdventures
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers

import SwiftData

struct DBConverter {
    @MainActor
    static func convert(appStore: AppStore, modelContext: ModelContext) async {
        let adventures = appStore.adventureRoot.listItems()
        insert(items: adventures, into: appStore.modelContainer.mainContext)
        
        let audios = appStore.audioRoot.listItems()
        insert(items: audios, into: appStore.modelContainer.mainContext)
        
        let characters = appStore.valueRoot.listItems()
        insert(items: characters, into: appStore.modelContainer.mainContext)
        
        let dice = appStore.diceRoot.listItems()
        insert(items: dice, into: appStore.modelContainer.mainContext)
        
        let maps = appStore.mapRoot.listItems()
        insert(items: maps, into: appStore.modelContainer.mainContext)
        
        let pdfs = appStore.pdfRoot.listItems()
        insert(items: pdfs, into: appStore.modelContainer.mainContext)
        
        let photos = appStore.photoRoot.listItems()
        insert(items: photos, into: appStore.modelContainer.mainContext, root: appStore.photoRootModel)
        
        let spaces = appStore.spaceRoot.listItems()
        insert(items: spaces, into: appStore.modelContainer.mainContext)
        
        let tables = appStore.tableRoot.listItems()
        insert(items: tables, into: appStore.modelContainer.mainContext)
        
        let weather = appStore.weatherRoot.listItems()
        insert(items: weather, into: appStore.modelContainer.mainContext)
    }
    
    static func insert(items: [RPGAdventures.AdventureModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                AdventureEntryDataModel(
                    itemId: item.id,
                    entryId: entry.id,
                    index: index,
                    name: entry.name,
                    content: entry.content
                )
            }
            entries.forEach { modelContext.insert($0) }
            
            let character = AdventureRPG.AdventureDataModel(
                itemId: item.id,
                photoId: item.photoId,
                entries: entries,
            )
            modelContext.insert(character)
            
            modelContext.insert(
                ItemDataModel(
                    id: item.id,
                    module: .adventure,
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
    
    static func insert(items: [RPGAudios.AudioModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                EntryDataModel(id: entry.id, index: index, parentId: item.id, childId: entry.audioId, item: nil)
            }
            modelContext.insert(
                ItemDataModel(id: item.id, module: .audio, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, url: item.fileUrl?.rawUrl, displayState: item.displayState, entries: entries)
            )
        }
    }
    
    static func insert(items: [RPGValues.ValueModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let character = CharacterRPG.CharacterDataModel(itemId: item.id, photoId: item.photoId, photos: item.photos, parentId: item.parentId)
            modelContext.insert(character)
            let entries = item.entries.enumerated().map { (index, entry) in
                CharacterEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.value, valueType: toCharacterValueType(entry.type), diceId: entry.diceId, valueId: entry.valueId)
            }
            entries.forEach { modelContext.insert($0) }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .value, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .character, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
        
        try? modelContext.save()
    }
    
    static func toCharacterValueType(_ value: RPGValues.ValueEntryModel.ValueType) -> CharacterRPG.CharacterEntryDataModel.ValueType {
        CharacterRPG.CharacterEntryDataModel.ValueType(rawValue: value.rawValue) ?? .text
    }
    
    public static func insert(items: [RPGDie.DiceModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let dice = item.entries.enumerated().map { (index, entry) in
                let dieModel =  DieDataModel(id: entry.id, index: index, die: convertDie(die: entry.die))
                modelContext.insert(dieModel)
                return dieModel
            }
            let config = DiceDataModel(
                itemId: item.id,
                sumUp: item.sumUp,
                modifier: item.modifier,
                percentDice: item.percentDice,
                compareOption: convertCompareOption(compareOption: item.compareOption),
                compareValue: item.compareValue,
                coupValues: convertCoupFumbleValues(values: item.coupValues),
                coupOnlyOnFirstDie: item.coupOnlyOnFirstDie,
                fumbleValues: convertCoupFumbleValues(values: item.fumbleValues),
                fumbleOnlyOnFirstDie: item.fumbleOnlyOnFirstDie,
                rerollOptions: convertRerollOptions(options: item.rerollOptions),
                reorderDice: item.reorderDice,
                addDiceEvery: item.addDiceEvery,
                dice: dice
            )
            modelContext.insert(config)
            modelContext.insert(
                ItemDataModel(id: item.id, module: .dice, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, displayState: item.displayState, entries: [])
            )
        }
    }
    
    private static func convertDie(die: RPGDie.RawDie) -> DiceRPG.RawDie {
        switch die.sides {
        case .four: DiceRPG.RawDie.four
        case .six: DiceRPG.RawDie.six
        case .eight: DiceRPG.RawDie.eight
        case .ten: DiceRPG.RawDie.ten
        case .twelve: DiceRPG.RawDie.twelve
        case .twenty: DiceRPG.RawDie.twenty
        case .number(let int): DiceRPG.RawDie(.number(int))
        @unknown default: .twenty
        }
    }
    
    private static func convertCompareOption(compareOption: RPGDie.DiceModel.CompareValue) -> DiceDataModel.CompareValue {
        switch compareOption {
        case .off: return .off
        case .lower: return .lower
        case .lowerEqual: return .lowerEqual
        case .equalHigher: return .equalHigher
        case .higher: return .higher
        @unknown default:
            fatalError()
        }
    }
    
    private static func convertCoupFumbleValues(values: [RPGDie.DiceModel.CoupFumbleOption]) -> [DiceDataModel.CoupFumbleOption] {
        values.map { value in
            switch value {
            case .result(let n): return .result(n)
            case .diceValue(let n): return .diceValue(n)
            @unknown default:
                fatalError()
            }
        }
    }
    
    private static func convertRerollOptions(options: [RPGDie.DiceModel.RerollOption]) -> [DiceDataModel.RerollOption] {
        options.map { option in
            DiceDataModel.RerollOption(number: option.number, value: option.value, maxDiceValue: option.maxDiceValue)
        }
    }
    
    static func insert(items: [RPGMaps.MapModel], into modelContext: ModelContext) {
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
                    module: .map,
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
    
    static func insert(items: [RPGPdfs.PdfModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            item.entries.enumerated().forEach { (index, entry) in
                let bookmark = PdfRPG.PdfEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.content, bounds: entry.bounds, pageLabel: entry.pageLabel)
                modelContext.insert(bookmark)
            }
            modelContext.insert(
                ItemDataModel(id: item.id, module: .pdf, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, url: item.fileUrl?.rawUrl, displayState: item.displayState)
            )
        }
    }
    
    @MainActor
    static func insert(items: [RPGPhotos.PhotoModel], into modelContext: ModelContext, root: PhotoRootModel) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        var models = (try? modelContext.fetch(fetchDesc)) ?? []
        
        var addedGroups: [UUID: [UUID]] = [:]
        
        items.forEach { item in
            guard !models.contains(where: { $0.id == item.id }) else { return }
            
            // Insert the photo model first with an empty entries array
            let photoModel = CoreRPG.ItemDataModel(
                id: item.id,
                module: .photo,
                name: item.name,
                information: item.description,
                category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure,
                tags: item.tags,
                url: item.fileUrl?.rawUrl,
                displayState: item.displayState,
                entries: [],
            )
            modelContext.insert(photoModel)
            var currentParentId: UUID? = nil
            var currentFolderModel: CoreRPG.ItemDataModel? = nil
            // Extract folder path components from the file URL
            if let url = item.fileUrl?.rawUrl {
                let folderComponents = url.pathComponents.dropFirst().dropLast() // drop root '/' and the file name
                for folderName in folderComponents {
                    // Find folder at this level with the same name and parent
                    let folderModel = models.first(where: { $0.category == .folder && $0.name == folderName && $0.parentId == currentParentId }) ??
                    {
                        // If not found, create
                        let newFolder = CoreRPG.ItemDataModel(
                            module: .photo,
                            name: folderName,
                            information: "",
                            category: .folder,
                            parentId: currentParentId
                        )
                        modelContext.insert(newFolder)
                        models.append(newFolder)
                        if let currentFolderModel {
                            root.editController.addItem(itemId: newFolder.id, in: currentFolderModel, folderId: currentParentId)
                        }
                        return newFolder
                    }()
                    currentParentId = folderModel.id
                    currentFolderModel = folderModel
                }
            }
            // If we found/created folders, add the photo to the deepest one
            if let folderModel = currentFolderModel {
                root.editController.addItem(itemId: item.id, in: folderModel, folderId: folderModel.id)
            }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                entry.photoId
            }
            addedGroups[item.id] = entries
        }
        
        addedGroups.forEach { (id, entries) in
            guard let model = CoreRPG.ItemDataModel.model(modelContext: modelContext, id: id) else { return }
            entries.forEach {
                root.editController.addGroup(childId: $0, model: model)
            }
        }
    }
    
    static func insert(items: [RPGSpaces.SpaceModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                EntryDataModel(id: entry.id, index: index, parentId: item.id, childId: entry.spaceId, item: nil)
            }
            modelContext.insert(
                ItemDataModel(id: item.id, module: .space, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure, tags: item.tags, url: item.fileUrl?.rawUrl, displayState: item.displayState, entries: entries)
            )
        }
    }
    
    static func insert(items: [RPGTables.TableModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let table = TableRPG.TableDataModel(itemId: item.id, diceId: item.diceId)
            modelContext.insert(table)
            let entries = item.entries.enumerated().map { (index, entry) in
                TableEntryDataModel(itemId: item.id, entryId: entry.id, index: index, name: entry.name, content: entry.content)
            }
            entries.forEach { modelContext.insert($0) }
            
            modelContext.insert(
                ItemDataModel(id: item.id, module: .table, name: item.name, information: item.description, category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .rules, tags: item.tags, url: nil, displayState: item.displayState)
            )
        }
        
        try? modelContext.save()
    }
    
    static func insert(items: [RPGWeathers.WeatherModel], into modelContext: ModelContext) {
        let fetchDesc = FetchDescriptor<CoreRPG.ItemDataModel>()
        let models = try? modelContext.fetch(fetchDesc)
        
        items.forEach { item in
            guard let models, !models.contains(where: { $0.id == item.id }) else { return }
            
            let mappedThickness = toWeatherThickness(item.cloudThickness)
            let mappedStorm = toWeatherStorm(item.stormType)
            
            let model = WeatherDataModel(
                itemId: item.id,
                photoId: item.photoId,
                time: item.time,
                cloudThickness: mappedThickness,
                stormType: mappedStorm,
                rainAngle: item.rainAngle,
                rainIntensity: item.rainIntensity,
                lightningFrequency: item.lightningFrequency,
                lightningMaxBolts: item.lightningMaxBolts,
                lightningForkProbability: item.lightningForkProbability
            )
            modelContext.insert(model)
            
            modelContext.insert(
                ItemDataModel(
                    id: item.id,
                    module: .weather,
                    name: item.name,
                    information: item.description,
                    category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure,
                    tags: item.tags,
                    url: nil,
                    displayState: item.displayState
                )
            )
        }
        try? modelContext.save()
    }
    
    static func toWeatherThickness(_ value: RPGWeathers.Cloud.Thickness) -> WeatherRPG.Cloud.Thickness {
        WeatherRPG.Cloud.Thickness(rawValue: value.rawValue) ?? .none
    }
    
    static func toWeatherStorm(_ value: RPGWeathers.Storm.Contents) -> WeatherRPG.Storm.Contents {
        WeatherRPG.Storm.Contents(rawValue: value.rawValue) ?? .none
    }
    
}
