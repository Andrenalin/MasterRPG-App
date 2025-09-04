// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .album
}

// MARK: - Import Controller

extension ItemController: ItemControllable {
    @MainActor func decodedItem(data: Data, version: Int) throws -> ItemDataCodableModel {
        let decoder = JSONDecoder()
        if version == ItemDataExportModel.Version.version_2025.rawValue {
            return try decoder.decode(ItemDataCodableModel.self, from: data)
        } else {
            do {
                let oldModel = try decoder.decode(PhotoModel.self, from: data)
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
        return FileUrl(fileId: id, url: url, location: .cloud, module: NetworkModules.photo.token)
    }
}
