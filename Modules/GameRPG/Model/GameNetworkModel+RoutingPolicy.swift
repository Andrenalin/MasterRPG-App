// @copyright André Trettin

import CoreRPG
import Foundation

// The routing/audience-policy extension — split out of GameNetworkModel.swift
// as its own file since it decides master/player/group/target audience for
// every message shape in the protocol and is worth isolating/unit-testing
// independently from the plain envelope model. See CODE_AUDIT §9.10.

extension GameNetworkModel {
    /// Bounds wall-clock ordering input before it can become the presentation
    /// baseline. Legacy envelopes use zero; current envelopes must carry a
    /// finite positive time that is not implausibly ahead of this device.
    /// See CODE_AUDIT_Game §9.12 — shared with MapRPG/SpaceRPG's identical policy.
    static let maximumFutureEventTimestampSkew = NetworkTimestampPolicy.maximumFutureSkew

    nonisolated static func acceptsEventTimestamp(
        _ timestamp: TimeInterval,
        now: TimeInterval = Date.now.timeIntervalSince1970
    ) -> Bool {
        if timestamp == 0 { return true }
        return timestamp.isFinite &&
            timestamp > 0 &&
            timestamp <= now + maximumFutureEventTimestampSkew
    }

    /// The complete, peer-visible Dice roll shape. Master-originated Dice
    /// presentation commands intentionally do not use this predicate: they
    /// retain their existing `.show`/`.store` behavior.
    var isDiceRollEvent: Bool {
        Self.isDiceRollEvent(
            type: type,
            subType: subType,
            purpose: purpose,
            targetId: targetId,
            data: data
        )
    }

    /// A normal player may publish only a complete Dice roll to the group.
    /// Legacy is retained for shipped V1 peers, whose envelopes predate the
    /// explicit event purpose but still carry the same full roll payload.
    var isPlayerDiceGroupEvent: Bool {
        sender.role == .player && isDiceRollEvent
    }

    /// Player-authored, small GroupSession events that may legitimately race
    /// the next master roster broadcast when a participant is joining. File
    /// presentations have their own availability/admission protocol and must
    /// never enter this short-lived transport deferral.
    var isDeferrablePlayerGroupEvent: Bool {
        guard sender.role == .player,
              masterState == nil,
              replyToMessageID == nil,
              !isJournalAdmissionOnly,
              journalPayloadDigest == nil,
              effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(timestamp)
        else { return false }

        if isPlayerDiceGroupEvent { return true }

        guard type == .update,
              purpose == .event,
              targetId == nil,
              data.data != nil
        else { return false }

        return (subType == .mapPin && data.type == .map) ||
            (subType == .spaceTransform && data.type == .space)
    }

    nonisolated private static func isDiceRollEvent(
        type: RPGMessageType,
        subType: RPGMessageActionType,
        purpose: GameMessagePurpose,
        targetId: UUID?,
        data: NetworkCodableDataType
    ) -> Bool {
        type == .update &&
            subType == .generic &&
            (purpose == .event || purpose == .legacy) &&
            targetId == nil &&
            data.type == .dice &&
            data.data != nil
    }

    /// The only file-backed presentation a player may publish directly to its
    /// peers. An explicit `.group` audience is transport metadata, not authority:
    /// repair requests must remain master-only even when a malformed or hostile
    /// sender stamps them as group-visible.
    var isPlayerFilePresentationEvent: Bool {
        guard sender.role == .player,
              type == .reveal,
              subType == .show,
              targetId == nil
        else { return false }

        // Current envelopes explicitly distinguish an event from a repair. V1
        // did not; only its full-payload shape is safe to expose to peers because
        // a data-less legacy reveal is ambiguous with an asset request.
        guard purpose == .event || (purpose == .legacy && data.data != nil) else {
            return false
        }

        return data.type == .photo || data.type == .pdf || data.type == .space
    }

    /// Lightweight Messenger half of a player Journal presentation. Journal
    /// callbacks do not expose their physical publisher, so receivers admit
    /// the later attachment only after seeing this same logical message from a
    /// concrete GroupSession participant.
    var isPlayerJournalAdmissionMetadata: Bool {
        journalAdmissionOnly == true &&
            isPlayerFilePresentationEvent &&
            data.data == nil &&
            journalPayloadDigest != nil &&
            messageID != nil
    }

    /// Master file payloads that may use GroupSessionJournal. The participant
    /// that authored a Journal attachment is not exposed by GroupActivities,
    /// so even authoritative master bytes require a matching Messenger half.
    /// Audio and Weather include targeted repairs; the other modules are the
    /// normal file-backed presentation set.
    var isMasterJournalEnvelope: Bool {
        guard sender.isMaster,
              messageID != nil,
              type == .reveal || type == .store
        else { return false }

        return switch data.type {
        case .audio, .weather, .map, .photo, .pdf, .space:
            true
        default:
            false
        }
    }

    var isMasterJournalAdmissionMetadata: Bool {
        journalAdmissionOnly == true &&
            isMasterJournalEnvelope &&
            data.data == nil &&
            journalPayloadDigest != nil
    }

    var isJournalAdmissionOnly: Bool {
        journalAdmissionOnly == true
    }

    /// Identifies every player-originated reveal in the peer-file protocol,
    /// including malformed shapes. Callers use this to fail closed instead of
    /// letting an explicit audience override the protocol tuple.
    var isPlayerFileReveal: Bool {
        guard sender.role == .player, type == .reveal else { return false }
        return data.type == .photo || data.type == .pdf || data.type == .space
    }

    /// Resolves legacy/automatic envelopes into the same routing policy used by
    /// newly-created messages.
    var effectiveAudience: GameMessageAudience {
        if targetId != nil { return .target }
        if isPlayerFilePresentationEvent { return .group }
        // A data-less legacy player reveal cannot be distinguished from an
        // asset request. Keep it master-only instead of letting the generic
        // file-reveal inference expose it to peers.
        if isPlayerFileReveal { return .master }
        let inferred = Self.inferredAudience(
            sender: sender,
            type: type,
            subType: subType,
            purpose: purpose,
            data: data
        )
        // A player may narrow an event to the master, but it cannot widen a
        // protocol-defined master-only message by stamping `.group`. This keeps
        // repair requests, acknowledgements, availability reports, screens, and
        // other canonicalization inputs off peer and bridge paths before module
        // handlers inspect them.
        if !sender.isMaster, inferred == .master { return .master }
        if audience != .automatic { return audience }
        return inferred
    }

    nonisolated static func inferredAudience(
        sender: GameSenderModel,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        purpose: GameMessagePurpose,
        data: NetworkCodableDataType,
        targetId: UUID? = nil
    ) -> GameMessageAudience {
        if targetId != nil { return .target }
        if sender.isMaster { return .group }
        if purpose == .assetRequest || subType == .ok || subType == .failed {
            return .master
        }

        if sender.role == .player,
           purpose == .event,
           type == .update,
           data.data != nil,
           ((subType == .mapPin && data.type == .map) ||
            (subType == .spaceTransform && data.type == .space)) {
            return .group
        }

        switch subType {
        case .audioList, .photoList, .pdfList, .spaceList, .screen,
             .mapState, .battleRound, .playAudio:
            return .master
        default:
            break
        }

        if data.type == .value || data.type == .audio || data.type == .map ||
            data.type == .table || data.type == .weather || data.type == .game {
            return .master
        }

        if sender.role == .player,
           Self.isDiceRollEvent(
               type: type,
               subType: subType,
               purpose: purpose,
               targetId: targetId,
               data: data
           ) {
            return .group
        }
        if type == .reveal, subType == .show,
           data.type == .photo || data.type == .pdf || data.type == .space {
            return .group
        }
        return .master
    }

    var isAcknowledgement: Bool {
        subType == .ok || subType == .failed
    }

    /// A master command that changes the player's current game presentation.
    /// These commands can race payloads delivered by another transport, so the
    /// intent is sequenced independently from transfer completion order.
    var isPresentationIntent: Bool {
        guard sender.isMaster || isPlayerFilePresentationEvent else { return false }

        if type == .reveal, subType == .show {
            return switch data.type {
            case .map, .photo, .pdf, .space, .table, .weather:
                true
            default:
                false
            }
        }

        guard type == .update else { return false }
        return switch data.type {
        case .map:
            subType == .mapState
        case .photo:
            subType != .photoList
        case .weather:
            false
        case .value:
            false
        case .space:
            subType != .spaceTransform && subType != .spaceList
        default:
            false
        }
    }

    var isFileBackedPresentation: Bool {
        guard isPresentationIntent else { return false }
        return data.type == .map ||
            data.type == .photo ||
            data.type == .pdf ||
            data.type == .space ||
            data.type == .weather
    }

    /// A mapState recovery payload is sent as `.reveal/.store`. It can promote
    /// a map to the current screen, but it repairs an earlier intent rather than
    /// declaring a new one.
    var isMapPresentationRepair: Bool {
        sender.isMaster && type == .reveal && subType == .store && data.type == .map
    }

    /// Older masters sent the targeted map-state companion with version zero.
    /// It may repair only the already intended map; it never advances intent.
    var isTargetedMapStatePresentationRepair: Bool {
        sender.isMaster &&
            targetId != nil &&
            type == .update &&
            subType == .mapState &&
            data.type == .map
    }

    /// A full Weather answer addressed to one player. SharePlay Journal entries
    /// are session-visible, but retaining the target keeps this replacement a
    /// repair for that player instead of a new presentation for the group.
    var isTargetedWeatherJournalRepair: Bool {
        sender.isMaster &&
            targetId != nil &&
            (type == .reveal || type == .store) &&
            data.type == .weather &&
            data.data != nil
    }

    var usesFileJournal: Bool {
        guard type == .reveal || type == .store else { return false }
        return data.usesFileJournal
    }
}

extension NetworkCodableDataType {
    var usesFileJournal: Bool {
        guard data != nil else { return false }
        switch type {
        case .pdf, .audio, .space, .photo, .map, .weather:
            return true
        default:
            return false
        }
    }
}
