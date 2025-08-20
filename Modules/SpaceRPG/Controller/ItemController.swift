// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: OldItemControllable {
    typealias Model = SpaceDataModel
    typealias ExchangeModel = SpaceModel

    let container: ModelContainer
    
    func item(for id: UUID) async -> SpaceModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.spaceModel()
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
}
