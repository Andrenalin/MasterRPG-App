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

// MARK: - Edit dice

extension EditController {
    func add(die: DieDataModel, to model: DiceDataModel) {
        let counter = model.config.dice.count
        let duplicate = die.duplicate(index: counter)
        let config = model.config
        config.dice.append(duplicate)
        model.config = config
    }
    
    func remove(die: DieDataModel, from model: DiceDataModel) {
        let config = model.config
        var dice = config.dice
        dice.removeAll(where: { $0.id == die.id })
        dice.enumerated().forEach { index, die in
            die.index = index
        }
        config.dice = dice
        model.config = config
    }
}
