// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(container: ModelContainer, module: NetworkModules) {
        self.itemCacheModel = ItemCacheModel()
        self.container = container
        self.module = module
    }
    let itemCacheModel: ItemCacheModel
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .album
    let module: NetworkModules
}


extension ItemController: ItemControllable {
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: NetworkModules.space.token)
    }
}

extension ItemController: ImportDataControllable {
    func replace(id: UUID, data: Data?, isInsert: Bool, shouldRepairLinks: Bool) {
        
    }
    
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(SpaceModel.self, from: data)
                return ConverterController.convert(old: oldModel)
            } catch {
                print(error)
                fatalError()
            }
        }
    }
}
