// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// What a message is follows from its shape alone: who sent it, its type and subtype, and
// whether it carries bytes. The transports and both controllers decide with these predicates.

extension GameNetworkModel {
    /// Bounds wall-clock ordering input before it can become a last-wins baseline: a finite,
    /// positive time that is not implausibly ahead of this device.
    static let maximumFutureEventTimestampSkew = NetworkTimestampPolicy.maximumFutureSkew

    nonisolated static func acceptsEventTimestamp(
        _ timestamp: TimeInterval,
        now: TimeInterval = Date.now.timeIntervalSince1970
    ) -> Bool {
        let isAccepted = timestamp.isFinite &&
            timestamp > 0 &&
            timestamp <= now + maximumFutureEventTimestampSkew
        // A sender whose clock runs far ahead loses every roll and pin move; at least say why.
        // See CODE_AUDIT_Game_Shareplay §5.26.
        if !isAccepted, timestamp.isFinite, timestamp > now {
            Logger.networking.warning("GameNetworkModel: Event dropped, its timestamp is \(Int(timestamp - now), privacy: .public) s ahead of this device's clock (limit \(Int(maximumFutureEventTimestampSkew), privacy: .public) s); the sender's clock is probably wrong")
        }
        return isAccepted
    }

    /// A player's answer to a master message, echoing its counter: received (`.ok`) or not
    /// usable (`.failed`).
    var isAcknowledgement: Bool {
        subType == .ok || subType == .failed
    }

    /// An availability report list in its exact protocol envelope: the list subtype of a
    /// file-backed module or Audio together with that module's item type. Checking the subtype
    /// alone would let a sender pair a benign list action with `.reveal`.
    var isReportListEnvelope: Bool {
        guard type == .update else { return false }
        return switch (subType, data.type) {
        case (.audioList, .audio), (.photoList, .photo), (.pdfList, .pdf), (.spaceList, .space):
            true
        default:
            false
        }
    }

    /// An availability list of a file-backed module or Audio, by subtype alone. The exact
    /// envelope check is `isReportListEnvelope`.
    var isReportList: Bool {
        switch subType {
        case .audioList, .photoList, .pdfList, .spaceList: true
        default: false
        }
    }

    /// A player's request for the bytes of an item the master named: the master's reveal or
    /// store echoed back with its counter and without bytes.
    var isAssetRequest: Bool {
        guard !sender.isMaster,
              data.data == nil,
              type == .reveal || type == .store,
              subType == .show || subType == .store
        else { return false }

        return switch data.type {
        case .audio, .dice, .map, .pdf, .photo, .space, .table, .weather:
            true
        default:
            false
        }
    }

    /// A complete Dice roll.
    var isDiceRollEvent: Bool {
        type == .update &&
            subType == .generic &&
            targetId == nil &&
            data.type == .dice &&
            data.data != nil
    }

    /// The small events a player publishes to the whole group.
    enum GroupEventKind: Sendable {
        case diceRoll
        case mapPin
        case spaceTransform
    }

    /// Which group event this message is by its shape alone, or `nil`: a complete Dice roll, a
    /// moved map pin, a Space transform.
    var groupEventKind: GroupEventKind? {
        if isDiceRollEvent { return .diceRoll }
        guard type == .update else { return nil }
        if subType == .mapPin && data.type == .map { return .mapPin }
        if subType == .spaceTransform && data.type == .space { return .spaceTransform }
        return nil
    }

    /// The small events a player publishes to the whole group: a Dice roll, a moved map pin, a
    /// Space transform. Everything else a player sends is for the master only.
    var isPlayerGroupEvent: Bool {
        guard sender.role == .player,
              masterState == nil,
              targetId == nil,
              let payload = data.data,
              payload.count <= GameLimits.maximumGroupEventPayloadBytes,
              GameNetworkModel.acceptsEventTimestamp(timestamp)
        else { return false }

        return groupEventKind != nil
    }

    /// A master message that changes what the players' game screen shows.
    var isPresentation: Bool {
        guard sender.isMaster else { return false }

        if type == .reveal {
            return switch data.type {
            // `.none` is the game master clearing the shown map; it orders with the shows.
            case .map, .photo, .pdf, .space, .table, .weather, .none:
                true
            default:
                false
            }
        }
        return type == .update && subType == .mapState && data.type == .map
    }

    /// A message that carries the package of a file-backed module: a reveal or store from the
    /// game master, or the file a player contributes. On SharePlay it travels as a Journal
    /// attachment.
    var carriesAsset: Bool {
        guard data.carriesAsset else { return false }
        if type == .reveal || type == .store { return true }
        return type == .update && subType == .generic && data.type != .map
    }
}

extension NetworkCodableDataType {
    var carriesAsset: Bool {
        guard data != nil else { return false }
        switch type {
        case .pdf, .audio, .space, .photo, .map, .weather:
            return true
        default:
            return false
        }
    }

    /// The same item and versions without its bytes.
    var reference: NetworkCodableDataType {
        NetworkCodableDataType(
            id: id,
            type: type,
            version: version,
            data: nil,
            assetVersion: assetVersion,
            contentVersion: contentVersion
        )
    }
}
