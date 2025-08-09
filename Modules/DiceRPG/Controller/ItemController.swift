// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable, Sendable {
    typealias Model = DiceDataModel
    typealias ExchangeModel = DiceModel

    let container: ModelContainer
    
    func item(for id: UUID) async -> DiceModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.itemModel()
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        nil
    }
}
