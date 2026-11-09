// @copyright André Trettin

import CoreRPG
import Foundation
import SpaceRPG

/// How a Space transform is sent: the game master and a player both stamp it causally, send it
/// and apply the stamped envelope to their own Space at once. Group transports do not echo a
/// sender's own event, and the master does not republish a player's transform, so this exact
/// envelope is applied optimistically and the viewer sees its own change as acknowledged. A
/// change of the ordering is made here, once.
extension GameRoot {
    /// Whether a message is a transform of a Space.
    static func isSpaceTransform(
        type: RPGMessageType,
        subtype: RPGMessageActionType,
        itemType: NetworkModules
    ) -> Bool {
        type == .update && subtype == .spaceTransform && itemType == .space
    }

    /// The timestamp an outgoing message carries: the causal one for a Space transform, now for
    /// anything else. `nil` when the Space refuses to stamp the transform, which is then not sent.
    func outgoingTimestamp(
        type: RPGMessageType,
        subtype: RPGMessageActionType,
        updated: NetworkCodableDataType
    ) -> TimeInterval? {
        guard Self.isSpaceTransform(type: type, subtype: subtype, itemType: updated.type) else {
            return Date.now.timeIntervalSince1970
        }
        return spaceRoot.spaceGameControllable.causalSpaceTransformTimestamp(
            itemId: updated.id,
            version: updated.effectiveAssetVersion
        )
    }

    /// Applies the stamped envelope of a sent Space transform to this device's own Space. Returns
    /// `false` when the Space rejects it; any other message returns `true`.
    func applyOwnSpaceTransform(_ message: GameNetworkModel) -> Bool {
        guard Self.isSpaceTransform(type: message.type, subtype: message.subType, itemType: message.data.type) else {
            return true
        }
        return spaceRoot.spaceGameControllable.applySpaceTransform(
            data: message.data,
            counter: message.counter,
            timestamp: message.timestamp
        )
    }
}
