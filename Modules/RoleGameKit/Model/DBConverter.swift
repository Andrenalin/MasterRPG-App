// @copyright André Trettin

import PhotoRPG
import SpaceRPG
import RPGPhotos
import RPGSpaces
import SwiftData

struct DBConverter {
    @MainActor
    static func convert(appStore: AppStore, modelContext: ModelContext) async {
        let photos = appStore.photoRoot.listPhotos()
        PhotoRPG.ConverterController.insertPhotos(photos: photos, into: appStore.sharedModelContainer.mainContext)
        
        let items = appStore.spaceRoot.listItems()
        SpaceRPG.ConverterController.insertSpaces(items: items, into: appStore.sharedModelContainer.mainContext)
    }
}
