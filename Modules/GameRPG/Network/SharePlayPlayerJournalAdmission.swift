// @copyright André Trettin

import CoreRPG
import Foundation

// See CODE_AUDIT §9.10 — moved out of GameNetworkController.swift, which owns
// and drives this admission actor but is otherwise unrelated to it.

struct SharePlayPlayerJournalAdmissionKey: Hashable, Sendable {
    let senderID: UUID
    let messageID: UUID
}

enum SharePlayPlayerJournalDisposition: Equatable, Sendable {
    case authorized
    case deferred
    case rejected
}

enum SharePlayJournalCallbackKind: Equatable, Sendable {
    case update
    case loadFailure
}

struct SharePlayDeferredJournalCallback: Sendable {
    let model: GameNetworkModel
    let kind: SharePlayJournalCallbackKind
}

enum SharePlayJournalAnnouncementAdmission: Sendable {
    case notAdmission
    case admitted([SharePlayDeferredJournalCallback])
    case rejected
}

/// Authenticates the otherwise anonymous player side of GroupSessionJournal.
///
/// Messenger supplies a physical participant ID, while Journal supplies only
/// developer-controlled metadata. The first accepted player message binds one
/// physical participant to one immutable logical sender for the session. A
/// Journal callback is released only after an admission metadata message with
/// the same sender-scoped message ID has arrived through Messenger.
actor SharePlayPlayerJournalAdmission {
    private typealias Fingerprint = GameNetworkModel.JournalFingerprint

    private struct Admission: Sendable {
        let participantID: UUID
        let fingerprint: Fingerprint
    }

    private struct PendingJournal: Sendable {
        let key: SharePlayPlayerJournalAdmissionKey
        let fingerprint: Fingerprint
        let callback: SharePlayDeferredJournalCallback
        let byteCount: Int
    }

    private let maximumAdmissionCount: Int
    private let maximumPendingCount: Int
    private let maximumPendingByteCount: Int
    /// `GroupSessionMessenger` can redeliver the same logical message well
    /// after the fact — e.g. following a participant reconnecting after being
    /// briefly unreachable (the same phenomenon `GameRelayAdmission` guards
    /// against; see its own doc). A purely count-capped `admissionOrder`
    /// could evict a legitimate admission's key long before such a
    /// legitimately-delayed retry arrives, letting a different participant
    /// newly claim that key. Age-based eviction keeps a key recognized for at
    /// least this long regardless of how much unrelated traffic passed
    /// through in between. See CODE_AUDIT_Reconnect §7.4.
    private let admissionRetentionWindow: Duration
    private let clock: ContinuousClock

    private var senderByDirectParticipant: [UUID: UUID] = [:]
    private var ownerParticipantBySender: [UUID: UUID] = [:]
    private var trustedMasterRelayParticipantID: UUID?
    private var admissionOrder: [SharePlayPlayerJournalAdmissionKey] = []
    private var admissionByKey: [SharePlayPlayerJournalAdmissionKey: Admission] = [:]
    private var admittedAt: [SharePlayPlayerJournalAdmissionKey: ContinuousClock.Instant] = [:]
    private var pendingJournals: [PendingJournal] = []
    private var pendingByteCount = 0
    /// Participant IDs known to have left the session. A late-redelivered
    /// message still tagged with a departed participant ID must never be
    /// allowed to (re-)establish a sender/participant binding out from under
    /// the legitimately reconnected participant's new ID — see
    /// `acceptsPlayerMessenger`'s guard below. Bounded like every other cache
    /// in this actor. See CODE_AUDIT_Reconnect §3.3.
    private var departedParticipantIds = PhysicalIdentityDenylist<UUID>(capacity: 64)

    init(
        maximumAdmissionCount: Int = 512,
        maximumPendingCount: Int = 16,
        maximumPendingByteCount: Int = 64 * ByteUnit.mebibyte,
        admissionRetentionWindow: Duration = .seconds(120),
        clock: ContinuousClock = ContinuousClock()
    ) {
        self.maximumAdmissionCount = max(1, maximumAdmissionCount)
        self.maximumPendingCount = max(1, maximumPendingCount)
        self.maximumPendingByteCount = max(0, maximumPendingByteCount)
        self.admissionRetentionWindow = admissionRetentionWindow
        self.clock = clock
    }

    /// Applies the SharePlay role policy and pins the transport participant to
    /// one player identity. A logical sender is likewise owned by only one live
    /// participant so a second participant cannot copy an established UUID.
    func acceptsPlayerMessenger(
        _ model: GameNetworkModel,
        participantID: UUID
    ) -> Bool {
        guard model.sender.role == .player,
              !departedParticipantIds.contains(participantID)
        else { return false }

        if trustedMasterRelayParticipantID == participantID {
            if let ownerParticipantID = ownerParticipantBySender[model.sender.id] {
                return ownerParticipantID == participantID
            }
            ownerParticipantBySender[model.sender.id] = participantID
            return true
        }

        if let boundSenderID = senderByDirectParticipant[participantID] {
            return boundSenderID == model.sender.id
        }
        if let boundParticipantID = ownerParticipantBySender[model.sender.id] {
            return boundParticipantID == participantID
        }

        senderByDirectParticipant[participantID] = model.sender.id
        ownerParticipantBySender[model.sender.id] = participantID
        return true
    }

    /// A remote player receives LAN-origin player events physically from the
    /// game master's SharePlay participant. Once PlayerController has accepted
    /// a complete master bootstrap and pinned that participant, it may relay
    /// multiple immutable logical player identities without being mistaken for
    /// a direct peer that is changing identity.
    func trustMasterRelay(participantID: UUID) -> Bool {
        if let trustedMasterRelayParticipantID {
            return trustedMasterRelayParticipantID == participantID
        }

        if let provisionalSenderID = senderByDirectParticipant.removeValue(
            forKey: participantID
        ), ownerParticipantBySender[provisionalSenderID] == participantID {
            ownerParticipantBySender[provisionalSenderID] = nil
        }
        trustedMasterRelayParticipantID = participantID
        return true
    }

    func isTrustedMasterRelay(participantID: UUID) -> Bool {
        trustedMasterRelayParticipantID == participantID
    }

    /// Records an accepted, physically attributed Messenger announcement and
    /// returns any Journal callbacks that arrived first for this exact sender.
    func admitAnnouncement(
        _ model: GameNetworkModel,
        participantID: UUID
    ) -> SharePlayJournalAnnouncementAdmission {
        let isPlayerAnnouncement = model.isPlayerJournalAdmissionMetadata
        let isMasterAnnouncement = model.isMasterJournalAdmissionMetadata
        guard isPlayerAnnouncement || isMasterAnnouncement else {
            return model.isJournalAdmissionOnly ? .rejected : .notAdmission
        }
        guard let key = Self.key(for: model) else { return .rejected }
        pruneExpiredAdmissions(before: clock.now)

        if isMasterAnnouncement {
            // Messenger metadata claiming master authority is admitted only
            // after PlayerController accepted a complete bootstrap and pinned
            // this exact physical participant.
            guard trustedMasterRelayParticipantID == participantID else { return .rejected }
        } else {
            guard ownerParticipantBySender[model.sender.id] == participantID else { return .rejected }
        }

        let fingerprint = Fingerprint(model)
        if let admission = admissionByKey[key] {
            // The first physically authenticated fingerprint remains immutable.
            // A copied sender/message ID cannot replace it or continue into the
            // normal presentation route.
            guard admission.participantID == participantID,
                  admission.fingerprint == fingerprint
            else { return .rejected }
        } else {
            admissionByKey[key] = Admission(
                participantID: participantID,
                fingerprint: fingerprint
            )
            admissionOrder.append(key)
            admittedAt[key] = clock.now
            while admissionOrder.count > maximumAdmissionCount {
                let evicted = admissionOrder.removeFirst()
                admissionByKey[evicted] = nil
                admittedAt[evicted] = nil
            }
        }

        var released: [SharePlayDeferredJournalCallback] = []
        pendingJournals.removeAll { pending in
            guard pending.key == key else { return false }
            pendingByteCount = max(0, pendingByteCount - pending.byteCount)
            if pending.fingerprint == fingerprint {
                released.append(pending.callback)
            }
            return true
        }
        return .admitted(released)
    }

    /// Authorizes a player Journal callback, or retains a bounded out-of-order
    /// callback until its Messenger announcement arrives. Non-presentation and
    /// legacy player attachments fail closed because they cannot be correlated.
    func disposition(
        forJournal model: GameNetworkModel,
        callbackKind: SharePlayJournalCallbackKind = .update
    ) -> SharePlayPlayerJournalDisposition {
        let isPlayerJournal = model.sender.role == .player &&
            model.isPlayerFilePresentationEvent
        let isMasterJournal = model.sender.isMaster && model.isMasterJournalEnvelope
        guard isPlayerJournal || isMasterJournal,
              !model.isJournalAdmissionOnly,
              let key = Self.key(for: model)
        else { return .rejected }
        let fingerprint = Fingerprint(model)
        if let admission = admissionByKey[key] {
            return admission.fingerprint == fingerprint ? .authorized : .rejected
        }

        let byteCount = model.data.data?.count ?? 0
        guard byteCount <= maximumPendingByteCount,
              pendingJournals.count < maximumPendingCount,
              pendingByteCount <= maximumPendingByteCount - byteCount
        else { return .rejected }

        // One system attachment can be observed repeatedly while its
        // announcement is in flight. Keep one pending copy per fingerprint.
        guard !pendingJournals.contains(where: {
            $0.key == key && $0.fingerprint == fingerprint
        }) else {
            return .deferred
        }
        pendingJournals.append(PendingJournal(
            key: key,
            fingerprint: fingerprint,
            callback: SharePlayDeferredJournalCallback(
                model: model,
                kind: callbackKind
            ),
            byteCount: byteCount
        ))
        pendingByteCount += byteCount
        return .deferred
    }

    func participantLeft(_ participantID: UUID) {
        // Remember this participant departed so a late-redelivered message
        // still tagged with its ID can never (re-)establish a binding out
        // from under the legitimately reconnected participant's new ID. See
        // `departedParticipantIds`'s own doc.
        departedParticipantIds.insert(participantID)
        let trustedMasterRelayLeft = trustedMasterRelayParticipantID == participantID
        let departedSenderIDs = Set(ownerParticipantBySender.compactMap { senderID, ownerID in
            ownerID == participantID ? senderID : nil
        })
        senderByDirectParticipant[participantID] = nil
        ownerParticipantBySender = ownerParticipantBySender.filter {
            $0.value != participantID
        }
        if trustedMasterRelayLeft {
            trustedMasterRelayParticipantID = nil
        }
        let departedAdmissionKeys = Set(admissionByKey.compactMap { key, admission in
            admission.participantID == participantID ? key : nil
        })
        admissionByKey = admissionByKey.filter {
            $0.value.participantID != participantID
        }
        admissionOrder.removeAll { departedAdmissionKeys.contains($0) }
        for key in departedAdmissionKeys {
            admittedAt[key] = nil
        }
        if trustedMasterRelayLeft {
            pendingJournals.removeAll()
            pendingByteCount = 0
        } else {
            pendingJournals.removeAll { pending in
                guard departedSenderIDs.contains(pending.key.senderID) else { return false }
                pendingByteCount = max(0, pendingByteCount - pending.byteCount)
                return true
            }
        }
    }

    func reset() {
        senderByDirectParticipant.removeAll()
        ownerParticipantBySender.removeAll()
        trustedMasterRelayParticipantID = nil
        admissionOrder.removeAll()
        admissionByKey.removeAll()
        admittedAt.removeAll()
        pendingJournals.removeAll()
        pendingByteCount = 0
        departedParticipantIds.removeAll()
    }

    /// `admissionOrder` is chronological (append-only, evicted from the
    /// front), so this stops at the first still-fresh entry rather than
    /// scanning the whole window. Mirrors `GameRelayAdmission.pruneExpired`.
    private func pruneExpiredAdmissions(before now: ContinuousClock.Instant) {
        while let oldest = admissionOrder.first,
              let admittedTime = admittedAt[oldest],
              now - admittedTime > admissionRetentionWindow {
            admissionOrder.removeFirst()
            admissionByKey[oldest] = nil
            admittedAt[oldest] = nil
        }
    }

    private static func key(for model: GameNetworkModel) -> SharePlayPlayerJournalAdmissionKey? {
        guard let messageID = model.messageID else { return nil }
        return SharePlayPlayerJournalAdmissionKey(
            senderID: model.sender.id,
            messageID: messageID
        )
    }
}
