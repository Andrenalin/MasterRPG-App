// @copyright André Trettin

import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import RPGAudios
import RPGPdfs
import RPGPhotos
import RPGSpaces
import SwiftData

struct DBConverter {
    @MainActor
    static func convert(appStore: AppStore, modelContext: ModelContext) async {
        let audios = appStore.audioRoot.listItems()
        AudioRPG.ConverterController.insert(items: audios, into: appStore.modelContainer.mainContext)

        let pdfs = appStore.pdfRoot.listItems()
        PdfRPG.ConverterController.insert(items: pdfs, into: appStore.modelContainer.mainContext)

        let photos = appStore.photoRoot.listItems()
        PhotoRPG.ConverterController.insert(items: photos, into: appStore.modelContainer.mainContext)
        
        let spaces = appStore.spaceRoot.listItems()
        SpaceRPG.ConverterController.insert(items: spaces, into: appStore.modelContainer.mainContext)

    }
}
