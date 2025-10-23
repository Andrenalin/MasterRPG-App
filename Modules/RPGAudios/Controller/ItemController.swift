// @copyright André Trettin

import AndrenalinKit
import CoreData
import Foundation

struct ItemController: Sendable {
    @MainActor
    init(root: AudioRoot, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.music, .playlist, .sound], networkModule: .audio)
    }

    weak var root: AudioRoot!
    let collectionCategory: ItemListCategory = .playlist
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = AudioModel
    
    var fileUrlDataController: FileUrlDataController? {
        root.fileUrlDataController
    }
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
    }
    
    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        guard let item = self.itemSync(for: model.itemId) else { return [] }
        
        return [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)] +
        item.entries.map { ItemRowModel(itemId: item.id, entryId: $0.audioId, typeId: itemDataModel.networkModule) }
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
        duplicate.fileUrl = try? await root.fileUrlDataController.duplicate(fileUrl: item.fileUrl, for: duplicate.id)
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
        return await root.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
}

extension ItemController {
    func didDelete(fileUrl: FileUrl?) async {
        guard let fileUrl else { return }
        root.fileUrlDataController.delete(fileUrl)
    }    
}
