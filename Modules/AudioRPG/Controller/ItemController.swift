// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import UniformTypeIdentifiers

struct ItemController: Sendable {
    @MainActor
    init(config: ModuleConfiguration, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config
        
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags, networkModule: config.module)
        self.collectionCategory = config.collectionCategory
        
        let fileUrlDataController = FileUrlDataController(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension, fileUrlAccess: self)
        self.fileUrlDataController = fileUrlDataController
    }

    let config: ModuleConfigurable
    var fileUrlDataController: FileUrlDataController?
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = AudioModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        guard let item = self.itemSync(for: model.itemId) else { return [] }
        
        return [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: config.module)] +
        item.entries.map { ItemRowModel(itemId: item.id, entryId: $0.audioId, typeId: config.module) }
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
        duplicate.fileUrl = try? await fileUrlDataController?.duplicate(fileUrl: item.fileUrl, for: duplicate.id)
        await replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
    }

    func fileUrl(for itemId: UUID) async -> FileUrl? {
        guard let item = await self.item(for: itemId) else { return nil }
        return item.fileUrl
    }
    
    func reset(fileUrl: FileUrl?, item: any ItemDataAccessable) async {
        guard let item = item as? AudioModel else { return }
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
        item.fileUrl = fileUrl
        await replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}

extension ItemController {
    func didDelete(fileUrl: FileUrl?) async {
        guard let fileUrl else { return }
        fileUrlDataController?.delete(fileUrl)
    }
}

extension ItemController {
    @MainActor func hasAudio(itemId: UUID) -> Bool {
        guard let model = itemSync(for: itemId) else { return false }
        guard model.specialCategory else { return model.url != nil }
        return model.entries.contains { hasAudio(itemId: $0.childId) }
    }
    
    @MainActor func audioList(itemId: UUID) -> [AudioModel] {
        guard let model = itemSync(for: itemId) else { return [] }
        guard model.specialCategory else {
            guard model.url != nil else { return [] }
            return [model]
        }
        return model.entries.flatMap { audioList(itemId: $0.childId) }
    }
}
