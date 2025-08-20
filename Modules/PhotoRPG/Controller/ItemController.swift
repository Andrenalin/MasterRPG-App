// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: OldItemControllable, Sendable {
    typealias Model = PhotoDataModel
    typealias ExchangeModel = PhotoModel

    let container: ModelContainer
    
    func item(for id: UUID) async -> PhotoModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.itemModel()
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
}
