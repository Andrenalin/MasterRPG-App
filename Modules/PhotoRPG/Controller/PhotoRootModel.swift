// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import RPGPhotos
import SwiftData
import Foundation


@MainActor @Observable
public final class PhotoRootModel {
    init() {
        let fileController = FileController()
        self.cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        self.fileController = fileController
    }

    let cacheController: CacheController
    let fileController: FileController

    public static func insertPhotos(photos: [PhotoModel], into modelContext: ModelContext) {

        photos.forEach { photo in
            //let predicate = Predicate<PhotoDataModel>({ \PhotoDataModel.id == photo.id })

            let fetchDesc = FetchDescriptor<PhotoDataModel>()
            let models = try? modelContext.fetch(fetchDesc)
            guard let models, !models.contains(where: { $0.id == photo.id }) else { return }

            let entries = photo.entries.enumerated().map { (index, entry) in
                PhotoEntryDataModel(id: entry.id, index: Int16(index), parentId: photo.id, photoId: entry.photoId, photo: nil)
            }
            modelContext.insert(
                PhotoDataModel(id: photo.id, name: photo.name, information: photo.description, category: CoreRPG.ItemListCategory(rawValue: photo.category.rawValue) ?? .adventure, tags: photo.tags, displayState: Int32(photo.displayState), degrees: photo.degrees, url: photo.fileUrl?.rawUrl, entries: entries)
            )
        }
    }
}
