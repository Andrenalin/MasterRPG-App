// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    let fileUrlDataController: FileUrlDataController? = nil
}

extension EditController: EditControllable {
    typealias Model = DiceDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    func createNewEntry(in model: DiceDataModel, childId: UUID) -> DiceEntryDataModel {
        DiceEntryDataModel(id: UUID(), index: model.entryModels.count, parentId: model.id, childId: childId, item: model)
    }
    
    func duplicate(model: DiceDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await actor.duplicate(url: nil)
            await actor.save()
        }
    }
}
