// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import os.log
import CoreData

#if canImport(PDFKit)
import PDFKit
#endif

#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

struct ItemController: Sendable {
    @MainActor
    init(root: PdfRoot, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.adventure, .character, .rules, .supplement], networkModule: .pdf)
    }
    
    weak var root: PdfRoot!
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = PdfModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
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
        await root.applyToAllEditController {
            await $0.didDelete(itemId: model.id)
        }
        await didDelete(fileUrl: model.fileUrl)
    }
    
    func didUpdate(model: ModelType) async {
        guard let model = model as? Model else { return }
        await root.applyToAllEditController {
            await $0.didUpdate(item: model)
        }
    }
    
    func duplicate(model: ItemRowModel) async {
        guard let item = await self.item(for: model.itemId) else { return }
        let duplicate = item.duplicate()
        Task { @MainActor in
            duplicate.fileUrl = try? await root.fileUrlDataController.duplicate(fileUrl: item.fileUrl, for: duplicate.id)
            replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
        }
    }
    
    func fileUrl(for itemId: UUID) async -> FileUrl? {
        guard let item = await self.item(for: itemId) else { return nil }
        return item.fileUrl
    }
    
    public func loadableUrl(for model: ItemRowModel) async -> URL? {
        guard let fileUrl = await self.item(for: model.itemId)?.fileUrl else { return nil }
        return await root.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
}

extension ItemController {
    func didDelete(fileUrl: FileUrl?) async {
        guard let fileUrl else { return }
        await root.cacheController.remove(itemId: fileUrl.fileId)
        root.fileUrlDataController.delete(fileUrl)
    }
}

extension ItemController {
#if !os(tvOS)
    func pdfDocument(for itemId: UUID) async -> PDFDocument? {
        guard var fileUrl = await self.item(for: itemId)?.fileUrl else { return nil }
        try? await root.fileUrlDataController.download(fileUrl: fileUrl)
        return await root.fileUrlDataController.url(for: fileUrl) { url -> PDFDocument? in
            guard let url else { return nil }
            return PDFDocument(url: url)
        }
    }
#endif
}
