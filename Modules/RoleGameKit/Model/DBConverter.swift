// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

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
        AdventureRPG.ConverterController.insert(items: adventures, into: appStore.modelContainer.mainContext)

        let audios = appStore.audioRoot.listItems()
        AudioRPG.ConverterController.insert(items: audios, into: appStore.modelContainer.mainContext)

        let characters = appStore.valueRoot.listItems()
        CharacterRPG.ConverterController.insert(items: characters, into: appStore.modelContainer.mainContext)

        let dice = appStore.diceRoot.listItems()
        DiceRPG.ConverterController.insert(items: dice, into: appStore.modelContainer.mainContext)

        let maps = appStore.mapRoot.listItems()
        MapRPG.ConverterController.insert(items: maps, into: appStore.modelContainer.mainContext)

        let pdfs = appStore.pdfRoot.listItems()
        PdfRPG.ConverterController.insert(items: pdfs, into: appStore.modelContainer.mainContext)

        let photos = appStore.photoRoot.listItems()
        PhotoRPG.ConverterController.insert(items: photos, into: appStore.modelContainer.mainContext, root: appStore.photoRootModel)
        
        let spaces = appStore.spaceRoot.listItems()
        SpaceRPG.ConverterController.insert(items: spaces, into: appStore.modelContainer.mainContext)

        let tables = appStore.tableRoot.listItems()
        TableRPG.ConverterController.insert(items: tables, into: appStore.modelContainer.mainContext)

        let weather = appStore.weatherRoot.listItems()
        WeatherRPG.ConverterController.insert(items: weather, into: appStore.modelContainer.mainContext)
    }
}
