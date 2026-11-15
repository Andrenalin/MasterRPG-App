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

    /// Whether a dice result may be applied to an occurrence: only while it waits for a player's
    /// roll, and, when the roll was handed to one player, only from that player. Any other roll
    /// that carries the occurrence's category (a stale roll, another player, the table rolled
    /// again) must not rewrite the generation tree. See CODE_AUDIT_26 §5.44.
    nonisolated static func accepts(
        isAwaitingPlayerRoll: Bool,
        awaitingPlayerId: UUID?,
        senderId: UUID?
    ) -> Bool {
        guard isAwaitingPlayerRoll else { return false }
        guard let awaitingPlayerId else { return true }
        return awaitingPlayerId == senderId
    }

    @discardableResult
    func consume(
        category: ResultCategory,
        diceResult: DiceResultModel,
        senderId: UUID? = nil
    ) -> Bool {
        guard category.module == .table,
              let occurrenceId = category.childId,
              let model = sessions[category.id],
              let occurrence = model.occurrence(id: occurrenceId),
              Self.accepts(
                isAwaitingPlayerRoll: occurrence.isAwaitingPlayerRoll,
                awaitingPlayerId: occurrence.awaitingPlayerId,
                senderId: senderId
              )
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
