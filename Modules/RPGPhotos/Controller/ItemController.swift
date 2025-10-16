// @copyright André Trettin

import AndrenalinKit
import Foundation
import UniformTypeIdentifiers

#if os(macOS)
internal import AppKit
#endif

struct ItemController: Sendable {
    @MainActor
    init(root: PhotoRoot, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.adventure, .map, .value, .weather], networkModule: .photo)
    }

    weak var root: PhotoRoot!
    let collectionCategory: ItemListCategory = .album
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = PhotoModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        guard let item = self.itemSync(for: model.itemId) else { return [] }

        return [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)] +
        item.entries.map { ItemRowModel(itemId: item.id, entryId: $0.photoId, typeId: itemDataModel.networkModule) }
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
