// @copyright André Trettin

import CoreRPG
import Foundation

extension GameNetworkModel {
    /// The identity of a player journal message for admission: every envelope field a peer
    /// could vary plus a digest recomputed from the payload bytes that actually arrived.
    ///
    /// The LAN master (`MasterController`) and the SharePlay admission
    /// (`SharePlayPlayerJournalAdmission`) each wrote this projection out field for field, so a
    /// field added to only one made the two admission checks disagree about whether two
    /// messages are the same. Both use this one type. See CODE_AUDIT_20 §9.5.
    struct JournalFingerprint: Equatable, Sendable {
        let envelopeVersion: Int
        let replyToMessageId: UUID?
        let masterId: UUID
        let sender: GameSenderModel
        let masterState: GameMasterStateModel?
        let counter: Int
        let proxyCounter: Int
        let type: RPGMessageType
        let subType: RPGMessageActionType
        let audience: GameMessageAudience
        let purpose: GameMessagePurpose
        let targetId: UUID?
        let itemId: UUID
        let module: NetworkModules
        let version: Int
        let assetVersion: Int?
        let contentVersion: Int?
        let timestamp: TimeInterval
        let journalPayloadDigest: Data?

        init(_ model: GameNetworkModel) {
            envelopeVersion = model.version
            replyToMessageId = model.replyToMessageID
            masterId = model.masterId
            sender = model.sender
            masterState = model.masterState
            counter = model.counter
            proxyCounter = model.proxyCounter
            type = model.type
            subType = model.subType
            audience = model.audience
            purpose = model.purpose
            targetId = model.targetId
            itemId = model.data.id
            module = model.data.type
            version = model.data.version
            assetVersion = model.data.assetVersion
            contentVersion = model.data.contentVersion
            timestamp = model.timestamp
            if let payload = model.data.data {
                // Never trust the digest copied into anonymous Journal metadata. Recompute it
                // from the bytes that actually loaded.
                journalPayloadDigest = GameNetworkModel.journalDigest(for: payload)
            } else {
                journalPayloadDigest = model.journalPayloadDigest
            }
        }
    }
}
