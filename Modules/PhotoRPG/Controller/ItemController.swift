// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config

        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
        
        let fileUrlDataController = FileUrlDataController(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension, fileUrlAccess: self)
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
        self.fileUrlDataController = fileUrlDataController
    }

    var cacheController: CacheController?
    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = PhotoModel
    
    var cacheControllable: ImageCacheControllable? { cacheController }
    @MainActor var linkRegisterControllable: LinkRegisterControllable { linkRegisterController }
    
    public func loadableUrl(for model: ItemRowModel) async -> URL? {
        guard let fileUrl = await self.item(for: model.itemId)?.fileUrl else { return nil }
        return await fileUrlDataController?.url(for: fileUrl, action: { $0 })
    }
}

extension ItemController: FileUrlAccessible {
    func saveFileUrl(fileUrl: FileUrl) async {
        guard let item = await item(for: fileUrl.fileId)?.copy() else { return }
        if let fileId = item.fileUrl?.fileId {
            await cacheController?.remove(itemId: fileId)
        }
        item.fileUrl = fileUrl
        await replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}

extension ItemController {
#if os(macOS)
    static let importImageTypes = AKImage.imageTypes.compactMap { UTType($0) }

    static func importImageFromProviders(_ itemProviders: [NSItemProvider], completion: @Sendable @escaping (Data?) -> Void) -> Bool {
        guard let provider = itemProviders.first else { return false }
        for type in importImageTypes {
            let typeIdentifier = type.identifier
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    DispatchQueue.main.async {
                        completion(data)
                    }
                }
                return true
            }
        }
        return false
    }
#endif
}

