// @copyright André Trettin

import CoreRPG
import Foundation

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
        timestamp.isFinite &&
            timestamp > 0 &&
            timestamp <= now + maximumFutureEventTimestampSkew
    }

    /// A player's answer to a master message, echoing its counter: received (`.ok`) or not
    /// usable (`.failed`).
    var isAcknowledgement: Bool {
        subType == .ok || subType == .failed
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

    /// The small events a player publishes to the whole group: a Dice roll, a moved map pin, a
    /// Space transform. Everything else a player sends is for the master only.
    var isPlayerGroupEvent: Bool {
        guard sender.role == .player,
              masterState == nil,
              targetId == nil,
              data.data != nil,
              GameNetworkModel.acceptsEventTimestamp(timestamp)
        else { return false }

        if isDiceRollEvent { return true }
        guard type == .update else { return false }
        return (subType == .mapPin && data.type == .map) ||
            (subType == .spaceTransform && data.type == .space)
    }

    /// A master message that changes what the players' game screen shows.
    var isPresentation: Bool {
        guard sender.isMaster else { return false }

        if type == .reveal {
            return switch data.type {
            case .map, .photo, .pdf, .space, .table, .weather:
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
