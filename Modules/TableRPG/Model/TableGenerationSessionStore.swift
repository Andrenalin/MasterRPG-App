// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import Observation

@MainActor @Observable
final class TableGenerationSessionStore {
    init(controller: TableGenerationController) {
        self.controller = controller
    }

    @ObservationIgnored private let controller: TableGenerationController
    @ObservationIgnored private var sessions: [UUID: TableGenerationModel] = [:]

    func register(_ model: TableGenerationModel) {
        sessions[model.id] = model
    }

    func unregister(_ model: TableGenerationModel) {
        sessions[model.id] = nil
    }

    @discardableResult
    func consume(
        category: ResultCategory,
        diceResult: DiceResultModel
    ) -> Bool {
        guard category.module == .table,
              let occurrenceId = category.childId,
              let model = sessions[category.id],
              let occurrence = model.occurrence(id: occurrenceId)
        else {
            return false
        }

        let result = diceResult.sum > 0
            ? diceResult.sum
            : diceResult.values.split(whereSeparator: { !$0.isNumber })
                .compactMap { Int($0) }
                .first
        guard let result else {
            model.errorMessage = String(
                localized: "The player dice result could not be read.",
                bundle: .module
            )
            return true
        }
        controller.apply(result: result, to: occurrence, model: model)
        return true
    }
}
