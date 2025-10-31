// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log
import UniformTypeIdentifiers

struct ItemController: Sendable {
    static var fileTypes: [UTType] { [.usdz] }
    static var filenameExtension: String { "usdz" }

    @MainActor init(dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: [.building, .item, .supplement], networkModule: .space)
        
        let fileUrlDataController = FileUrlDataController(moduleFolder: NetworkModules.space.token, fileTypes: ItemController.fileTypes, filenameExtension: ItemController.filenameExtension, fileUrlAccess: self)
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
        self.fileUrlDataController = fileUrlDataController
    }

    var cacheController: CacheController?
    var fileUrlDataController: FileUrlDataController?
    let collectionCategory: ItemListCategory = .album
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = SpaceModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }
    
    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        guard let item = self.itemSync(for: model.itemId) else { return [] }

        return [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)] +
        item.entries.map { ItemRowModel(itemId: item.id, entryId: $0.spaceId, typeId: itemDataModel.networkModule) }
    }

    @MainActor
    func createLink(model: ItemRowModel) -> String {
        let itemId = model.entryId ?? model.itemId
        guard let item = self.itemSync(for: itemId) else { return "" }
        return item.url(linkNumber: 0)
    }
    
    func didDelete(model: ModelType) async {
        guard let model = model as? Model else { return }
//        await root.applyToAllEditController {
//            await $0.didDelete(itemId: model.id)
//        }
        await didDelete(fileUrl: model.fileUrl)
    }
    
    func didUpdate(model: ModelType) async {
        guard let model = model as? Model else { return }
//        await root.applyToAllEditController {
//            await $0.didUpdate(item: model)
//        }
    }
    
    func duplicate(model: ItemRowModel) async {
        guard let item = await self.item(for: model.itemId) else { return }
        let duplicate = item.duplicate()
        duplicate.fileUrl = try? await fileUrlDataController?.duplicate(fileUrl: item.fileUrl, for: duplicate.id)
        await replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
    }

    func fileUrl(for itemId: UUID) async -> FileUrl? {
        guard let item = await self.item(for: itemId) else { return nil }
        return item.fileUrl
    }
    
    func reset(fileUrl: FileUrl?, item: any ItemDataAccessable) async {
        guard let item = item as? SpaceModel else { return }
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
