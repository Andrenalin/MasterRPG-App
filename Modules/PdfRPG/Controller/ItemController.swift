// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import UniformTypeIdentifiers

#if canImport(PDFKit)
import PDFKit
#endif

//#if canImport(QuickLookThumbnailing)
//import QuickLookThumbnailing
//#endif

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable
        
        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags, networkModule: config.module)
        self.collectionCategory = config.collectionCategory

        let fileUrlDataController = FileUrlDataController(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension, fileUrlAccess: self)
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
        self.fileUrlDataController = fileUrlDataController
    }
    
    let config: ModuleConfigurable
    var cacheController: CacheController?
    var fileUrlDataController: FileUrlDataController?
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = PdfModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        let item = itemOrEmpty(for: model.itemId)
        guard !item.entries.isEmpty else {
            return [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)]
        }
        return itemOrEmpty(for: model.itemId).entries.map {
            ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: itemDataModel.networkModule)
        }
    }
    
    @MainActor
    func createLink(model: ItemRowModel) -> String {
        let itemId = model.entryId ?? model.itemId
        guard let item = self.itemSync(for: itemId) else { return "" }
        return item.url(linkNumber: 0)
    }
    
    func didDelete(model: ModelType) async {
        guard let model = model as? Model else { return }
        await didDelete(fileUrl: model.fileUrl)
    }
    
    func didUpdate(model: ModelType) async {
    }
    
    func duplicate(model: ItemRowModel) async {
        guard let item = await self.item(for: model.itemId) else { return }
        let duplicate = item.duplicate()
        Task { @MainActor in
            duplicate.fileUrl = try? await fileUrlDataController?.duplicate(fileUrl: item.fileUrl, for: duplicate.id)
            replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
        }
    }
    
    func fileUrl(for itemId: UUID) async -> FileUrl? {
        guard let item = await self.item(for: itemId) else { return nil }
        return item.fileUrl
    }
    
    func reset(fileUrl: FileUrl?, item: any ItemDataAccessable) async {
        guard let item = item as? PdfModel else { return }
        if let oldFileUlr = item.fileUrl {
            await cacheController?.remove(itemId: oldFileUlr.fileId)
        }
        item.fileUrl = fileUrl
    }

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
    func didDelete(fileUrl: FileUrl?) async {
        guard let fileUrl else { return }
        await cacheController?.remove(itemId: fileUrl.fileId)
        fileUrlDataController?.delete(fileUrl)
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
