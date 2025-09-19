// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(container: ModelContainer, module: NetworkModules) {
        self.cacheModel = ItemCacheModel()
        self.container = container
        self.module = module
    }
    let cacheModel: ItemCacheModel
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .playlist
    let module: NetworkModules
}

extension ItemController: ItemControllable {
    @MainActor func hasAudio(itemId: UUID) -> Bool {
        guard let model = item(for: itemId) else { return false }
        guard model.specialCategory else { return model.url != nil }
        return model.entries.contains { hasAudio(itemId: $0.childId) }
    }
    
    @MainActor func audioList(itemId: UUID) -> [ItemDataCodableModel] {
        guard let model = item(for: itemId) else { return [] }
        guard model.specialCategory else {
            guard model.url != nil, let item = itemModel(model: model) else { return [] }
            return [item]
        }
        return model.entries.flatMap { audioList(itemId: $0.childId) }
    }

    @MainActor func itemModel(model: ItemDataModel) -> ItemDataCodableModel? {
        itemDataCodableModel(for: model.id)
    }
}

// MARK: - Import Controller

extension ItemController {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(AudioModel.self, from: data)
                return ConverterController.convert(old: oldModel)
            } catch {
                print(error)
                fatalError()
            }
        }
    }
    
    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        let model = itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
    
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: NetworkModules.audio.token)
    }
}
