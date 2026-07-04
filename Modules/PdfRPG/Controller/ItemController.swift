// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, dataController: DataController?, linkRegisterController: LinkRegisterController) {
        self.config = config
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterController
        
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
    let linkRegisterController: LinkRegisterController
}

extension ItemController: ItemControllable {
    typealias Model = PdfModel
    
    var cacheControllable: ImageCacheControllable? { cacheController }
}

extension ItemController: FileUrlAccessible {
    // Isolated witness for the async requirement — callers already await.
    @MainActor func saveFileUrl(fileUrl: FileUrl) async {
        guard let item = await item(for: fileUrl.fileId)?.copy() else { return }
        if let fileId = item.fileUrl?.fileId {
            await cacheController?.remove(itemId: fileId)
        }
        item.fileUrl = fileUrl
        replace(model: item, isInsert: false)
    }
}

extension ItemController {
#if !os(tvOS)
    func pdfDocument(for itemId: UUID) async -> PDFDocument? {
        guard let fileUrl = await self.item(for: itemId)?.fileUrl else { return nil }
        try? await fileUrlDataController?.download(fileUrl: fileUrl)
        return await fileUrlDataController?.url(for: fileUrl) { url -> PDFDocument? in
            guard let url else { return nil }
            return PDFDocument(url: url)
        }
    }
#endif
}
