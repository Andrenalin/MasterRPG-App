// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable, Sendable {
    typealias Model = PdfDataModel
    typealias ExchangeModel = PdfModel

    let container: ModelContainer
    
    func item(for id: UUID) async -> PdfModel? {
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
