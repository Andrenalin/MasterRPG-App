// @copyright André Trettin

import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG

import RPGAudios
import RPGDie
import RPGPdfs
import RPGPhotos
import RPGSpaces

import SwiftData

struct DBConverter {
    @MainActor
    static func convert(appStore: AppStore, modelContext: ModelContext) async {
        let audios = appStore.audioRoot.listItems()
        AudioRPG.ConverterController.insert(items: audios, into: appStore.modelContainer.mainContext)

        let dice = appStore.diceRoot.listItems()
        DiceRPG.ConverterController.insert(items: dice, into: appStore.modelContainer.mainContext)

        let pdfs = appStore.pdfRoot.listItems()
        PdfRPG.ConverterController.insert(items: pdfs, into: appStore.modelContainer.mainContext)

        let photos = appStore.photoRoot.listItems()
        PhotoRPG.ConverterController.insert(items: photos, into: appStore.modelContainer.mainContext, root: appStore.photoRootModel)
        
        let spaces = appStore.spaceRoot.listItems()
        SpaceRPG.ConverterController.insert(items: spaces, into: appStore.modelContainer.mainContext)

    }
}
