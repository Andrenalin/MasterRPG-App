// @copyright André Trettin

import AudioRPG
import PhotoRPG
import SpaceRPG
import RPGAudios
import RPGPhotos
import RPGSpaces
import SwiftData

struct DBConverter {
    @MainActor
    static func convert(appStore: AppStore, modelContext: ModelContext) async {
        let audios = appStore.audioRoot.listItems()
        AudioRPG.ConverterController.insert(items: audios, into: appStore.modelContainer.mainContext)

        let photos = appStore.photoRoot.listPhotos()
        PhotoRPG.ConverterController.insert(items: photos, into: appStore.modelContainer.mainContext)
        
        let spaces = appStore.spaceRoot.listItems()
        SpaceRPG.ConverterController.insert(items: spaces, into: appStore.modelContainer.mainContext)

    }
}
