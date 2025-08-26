// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .bookshelf
}

extension ItemController: ItemControllable {
    func encodedItemData(for id: UUID) async throws -> Data? {
        let encoder = JSONEncoder()
        let model = await itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
}
