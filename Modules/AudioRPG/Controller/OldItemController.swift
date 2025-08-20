// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct OldItemController: OldItemControllable, Sendable {
    typealias Model = AudioDataModel
    typealias ExchangeModel = AudioModel
    
    let container: ModelContainer
    
    func item(for id: UUID) async -> AudioModel? {
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
