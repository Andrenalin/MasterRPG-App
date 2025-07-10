// @copyright André Trettin

import PhotoRPG
import RPGPhotos
import SwiftData

struct DBConverter {
    @MainActor
    static func convert(appStore: AppStore, modelContext: ModelContext) async {
        let photos = appStore.photoRoot.listPhotos()
        PhotoRootModel.insertPhotos(photos: photos, into: appStore.sharedModelContainer.mainContext)
    }
}
