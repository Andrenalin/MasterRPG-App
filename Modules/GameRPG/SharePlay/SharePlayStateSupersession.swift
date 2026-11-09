// @copyright André Trettin

import CoreRPG
import Foundation

/// Remembers the newest state update sent per entity, so a retry of an older one is dropped.
///
/// A whole-message retry goes out after the messages sent meanwhile; a pin position or a battle
/// round that is resent then would be applied after a newer one. Only updates that replace the
/// whole state of their entity qualify: a dice roll or a value change is an event, and a later
/// one does not make an earlier one obsolete. See CODE_AUDIT_Game_Shareplay §5.18.
struct SharePlayStateSupersession: Sendable {
    private struct Key: Hashable, Sendable {
        let subType: RPGMessageActionType
        let module: NetworkModules
        let itemId: UUID
        let senderId: UUID
        let participantId: UUID?
    }

    private var newestCounters: [Key: Int] = [:]
    static let maximumEntries = 1_024

    static func replacesState(_ model: GameNetworkModel) -> Bool {
        guard model.type == .update else { return false }
        switch model.subType {
        case .mapPin, .spaceTransform, .battleRound, .tableWeather:
            return true
        default:
            return false
        }
    }

    private static func key(_ model: GameNetworkModel, participantId: UUID?) -> Key {
        Key(subType: model.subType, module: model.data.type, itemId: model.data.id, senderId: model.sender.id, participantId: participantId)
    }

    /// Notes a first send of `model`.
    mutating func noteSent(_ model: GameNetworkModel, participantId: UUID?) {
        guard Self.replacesState(model) else { return }
        if newestCounters.count >= Self.maximumEntries {
            newestCounters.removeAll()
        }
        let key = Self.key(model, participantId: participantId)
        newestCounters[key] = max(newestCounters[key] ?? 0, model.counter)
    }

    /// Whether a newer update of the same entity was sent after `model`.
    func isSuperseded(_ model: GameNetworkModel, participantId: UUID?) -> Bool {
        guard Self.replacesState(model),
              let newest = newestCounters[Self.key(model, participantId: participantId)]
        else { return false }
        return newest > model.counter
    }

    mutating func reset() {
        newestCounters.removeAll()
    }
}
