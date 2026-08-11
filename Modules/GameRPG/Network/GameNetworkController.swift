// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI
import GroupActivities

private struct GameRelayAdmissionKey: Hashable, Sendable {
    let senderID: UUID
    let messageID: UUID
    let hasData: Bool
}

/// Stops transport retries from crossing a LAN/SharePlay bridge repeatedly.
/// Message identity is sender-scoped because independently generated UUIDs are
/// not globally coordinated. Metadata and its later full Journal payload remain
/// distinct admissions.
private actor GameRelayAdmission {
    private let limit: Int
    private var order: [GameRelayAdmissionKey] = []
    private var keys: Set<GameRelayAdmissionKey> = []

    init(limit: Int = 512) {
        self.limit = limit
    }

    func admit(_ model: GameNetworkModel) -> Bool {
        guard let messageID = model.messageID else {
            // V1 has no stable message identity. Its controller-side pipeline
            // still deduplicates positive counters; do not guess for counter zero.
            return true
        }
        let key = GameRelayAdmissionKey(
            senderID: model.sender.id,
            messageID: messageID,
            hasData: model.data.data != nil
        )
        guard keys.insert(key).inserted else { return false }
        order.append(key)
        while order.count > limit {
            keys.remove(order.removeFirst())
        }
        return true
    }

    func reset() {
        order.removeAll()
        keys.removeAll()
    }
}

private struct SharePlayDeferredPeerGroupEvent: Sendable {
    let model: GameNetworkModel
    let participantID: UUID
}

/// Holds a very small amount of peer intent across the one ordering window in
/// which GroupSessionMessenger can surface a new player's event before the
/// master's roster broadcast. The next accepted master-state update drains the
/// entire batch; entries that are still unknown fail closed during revalidation.
private actor SharePlayDeferredPeerGroupEvents {
    private enum LogicalIdentity: Hashable, Sendable {
        case current(senderID: UUID, messageID: UUID)
        case legacy(
            senderID: UUID,
            counter: Int,
            type: RPGMessageType,
            subType: RPGMessageActionType,
            itemId: UUID,
            timestampBits: UInt64
        )
    }

    private struct Key: Hashable, Sendable {
        let participantID: UUID
        let identity: LogicalIdentity
    }

    private struct Pending: Sendable {
        let event: SharePlayDeferredPeerGroupEvent
        let retainedByteCount: Int
    }

    private let maximumEventCount: Int
    private let maximumEventByteCount: Int
    private let maximumTotalByteCount: Int
    private var order: [Key] = []
    private var pendingByKey: [Key: Pending] = [:]
    private var totalByteCount = 0

    init(
        maximumEventCount: Int = 32,
        maximumEventByteCount: Int = 64 * 1_024,
        maximumTotalByteCount: Int = 512 * 1_024
    ) {
        self.maximumEventCount = max(1, maximumEventCount)
        self.maximumEventByteCount = max(0, maximumEventByteCount)
        self.maximumTotalByteCount = max(0, maximumTotalByteCount)
    }

    func retain(_ model: GameNetworkModel, participantID: UUID) -> Bool {
        guard model.isDeferrablePlayerGroupEvent else { return false }
        let payloadByteCount = model.data.data?.count ?? 0
        let senderNameByteCount = model.sender.name.utf8.count
        guard payloadByteCount <= maximumEventByteCount,
              senderNameByteCount <= maximumEventByteCount - payloadByteCount
        else { return false }
        let retainedByteCount = payloadByteCount + senderNameByteCount

        let key = Key(
            participantID: participantID,
            identity: Self.logicalIdentity(for: model)
        )
        if pendingByKey[key] != nil {
            // Messenger retries should not consume another slot.
            return true
        }
        guard order.count < maximumEventCount,
              retainedByteCount <= maximumTotalByteCount,
              totalByteCount <= maximumTotalByteCount - retainedByteCount
        else { return false }

        order.append(key)
        pendingByKey[key] = Pending(
            event: SharePlayDeferredPeerGroupEvent(
                model: model,
                participantID: participantID
            ),
            retainedByteCount: retainedByteCount
        )
        totalByteCount += retainedByteCount
        return true
    }

    func drain() -> [SharePlayDeferredPeerGroupEvent] {
        let events = order.compactMap { pendingByKey[$0]?.event }
        reset()
        return events
    }

    func participantLeft(_ participantID: UUID) {
        let removedKeys = order.filter { $0.participantID == participantID }
        for key in removedKeys {
            if let removed = pendingByKey.removeValue(forKey: key) {
                totalByteCount = max(
                    0,
                    totalByteCount - removed.retainedByteCount
                )
            }
        }
        order.removeAll { $0.participantID == participantID }
    }

    func reset() {
        order.removeAll()
        pendingByKey.removeAll()
        totalByteCount = 0
    }

    private static func logicalIdentity(
        for model: GameNetworkModel
    ) -> LogicalIdentity {
        if let messageID = model.messageID {
            return .current(senderID: model.sender.id, messageID: messageID)
        }
        return .legacy(
            senderID: model.sender.id,
            counter: model.counter,
            type: model.type,
            subType: model.subType,
            itemId: model.data.id,
            timestampBits: model.timestamp.bitPattern
        )
    }
}

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
    private struct Fingerprint: Equatable, Sendable {
        let envelopeVersion: Int
        let replyToMessageID: UUID?
        let masterID: UUID
        let sender: GameSenderModel
        let masterState: GameMasterStateModel?
        let counter: Int
        let proxyCounter: Int
        let type: RPGMessageType
        let subType: RPGMessageActionType
        let audience: GameMessageAudience
        let purpose: GameMessagePurpose
        let targetID: UUID?
        let itemId: UUID
        let module: NetworkModules
        let version: Int
        let assetVersion: Int?
        let contentVersion: Int?
        let timestamp: TimeInterval
        let journalPayloadDigest: Data?

        init(_ model: GameNetworkModel) {
            envelopeVersion = model.version
            replyToMessageID = model.replyToMessageID
            masterID = model.masterId
            sender = model.sender
            masterState = model.masterState
            counter = model.counter
            proxyCounter = model.proxyCounter
            type = model.type
            subType = model.subType
            audience = model.audience
            purpose = model.purpose
            targetID = model.targetId
            itemId = model.data.id
            module = model.data.type
            version = model.data.version
            assetVersion = model.data.assetVersion
            contentVersion = model.data.contentVersion
            timestamp = model.timestamp
            if let payload = model.data.data {
                // Never trust the digest copied into anonymous Journal
                // metadata. Recompute it from the bytes that actually loaded.
                journalPayloadDigest = GameNetworkModel.journalDigest(for: payload)
            } else {
                journalPayloadDigest = model.journalPayloadDigest
            }
        }
    }

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

    private var senderByDirectParticipant: [UUID: UUID] = [:]
    private var ownerParticipantBySender: [UUID: UUID] = [:]
    private var trustedMasterRelayParticipantID: UUID?
    private var admissionOrder: [SharePlayPlayerJournalAdmissionKey] = []
    private var admissionByKey: [SharePlayPlayerJournalAdmissionKey: Admission] = [:]
    private var pendingJournals: [PendingJournal] = []
    private var pendingByteCount = 0

    init(
        maximumAdmissionCount: Int = 512,
        maximumPendingCount: Int = 16,
        maximumPendingByteCount: Int = 64 * 1_024 * 1_024
    ) {
        self.maximumAdmissionCount = max(1, maximumAdmissionCount)
        self.maximumPendingCount = max(1, maximumPendingCount)
        self.maximumPendingByteCount = max(0, maximumPendingByteCount)
    }

    /// Applies the SharePlay role policy and pins the transport participant to
    /// one player identity. A logical sender is likewise owned by only one live
    /// participant so a second participant cannot copy an established UUID.
    func acceptsPlayerMessenger(
        _ model: GameNetworkModel,
        participantID: UUID
    ) -> Bool {
        guard model.sender.role == .player else { return false }

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
            while admissionOrder.count > maximumAdmissionCount {
                admissionByKey[admissionOrder.removeFirst()] = nil
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
        pendingJournals.removeAll()
        pendingByteCount = 0
    }

    private static func key(for model: GameNetworkModel) -> SharePlayPlayerJournalAdmissionKey? {
        guard let messageID = model.messageID else { return nil }
        return SharePlayPlayerJournalAdmissionKey(
            senderID: model.sender.id,
            messageID: messageID
        )
    }
}

/// Unified network controller for both direct-play and proxy-relay modes.
///
/// - `proxy: false` — direct mode: owns SharePlay, fans out received data to all peers.
/// - `proxy: true`  — proxy mode: no SharePlay, no fan-out (avoids relay loops).
///
/// `GameRoot` holds two instances: `networkStore` (direct) and `networkProxyStore` (proxy).
final class GameNetworkController: Sendable {
    let proxy: Bool
    let model: GameNetworkControllerModel
    private let relayAdmission = GameRelayAdmission()
    private let sharePlayPlayerJournalAdmission = SharePlayPlayerJournalAdmission()
    private let sharePlayDeferredPeerGroupEvents = SharePlayDeferredPeerGroupEvents()

    @MainActor
    let sharePlayStore: RPGSharePlayController

    /// Only accepted peer-visible events cross a transport bridge. Reports,
    /// acknowledgements, repair requests, screens, and canonicalization inputs
    /// are master-only and must stop at the game master.
    nonisolated static func shouldRelayToLAN(_ model: GameNetworkModel) -> Bool {
        guard !model.isJournalAdmissionOnly else { return false }
        if model.sender.isMaster {
            return model.effectiveAudience == .group
        }
        guard model.sender.role == .player,
              model.effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else { return false }

        // Player Photo/PDF/Space reveals have one peer-visible protocol shape.
        // In particular, `.assetRequest` remains master-only even if a sender
        // explicitly stamps the envelope with `.group`.
        if model.isPlayerFileReveal {
            return model.isPlayerFilePresentationEvent
        }
        if model.data.type == .dice {
            return model.isPlayerDiceGroupEvent
        }
        return true
    }

    // MARK: Static builders

    @MainActor static let defaultMasterStoreBuilder: (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = { name, delegate in
        MasterNetworkController(name: name, delegate: delegate, listnerBuilder: MasterNetworkController.gameListnerBuilder())
    }

    @MainActor static let directPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, delegate: delegate)
    }

    @MainActor static let proxyPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, proxy: true, delegate: delegate)
    }

    // MARK: Inits

    /// Designated init — used by tests to inject spy implementations.
    @MainActor
    init(
        name: String,
        proxy: Bool,
        masterBuilder: @escaping (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable,
        playerBuilder: @escaping (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable
    ) {
        self.proxy = proxy
        self.sharePlayStore = RPGSharePlay.store
        self.model = GameNetworkControllerModel(name: name)
        let masterStore = masterBuilder(name, self)
        let playerStore = playerBuilder(name, self)
        model.setControllers(master: masterStore, player: playerStore)
        Logger.networking.debug("GameNetworkController: Init \(name, privacy: .public) proxy=\(proxy)")
    }

    /// Convenience init for direct (non-proxy) mode.
    @MainActor
    convenience init(name: String = "") {
        self.init(
            name: name,
            proxy: false,
            masterBuilder: Self.defaultMasterStoreBuilder,
            playerBuilder: Self.directPlayerStoreBuilder
        )
    }

    /// Convenience init for proxy mode.
    @MainActor
    convenience init(proxyName name: String = "") {
        self.init(
            name: name,
            proxy: true,
            masterBuilder: Self.defaultMasterStoreBuilder,
            playerBuilder: Self.proxyPlayerStoreBuilder
        )
    }

    deinit {
        let name = model.name
        Logger.networking.debug("GameNetworkController: deinit \(name, privacy: .public)")
    }

    /// Sets up SharePlay integration. Only meaningful in direct (non-proxy) mode.
    @MainActor
    func setup(gameModel: GameRootModel) {
        guard !model.isSetup else { return }
        sharePlayStore.setup(gameModel: gameModel)
        sharePlayStore.delegate = self
        model.didSetup()
    }

    @MainActor
    func setupLocal() {
        model.setLocalPlayers(to: true)
    }
}

// MARK: - Control

extension GameNetworkController {
    @MainActor
    func startMasterGame(game: GameConfigModel, titleImage: AKImage?) async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start master game \(name, privacy: .public)")
        model.masterStore?.startStreaming()
        if !proxy && sharePlayStore.canActivateSharePlay {
            // Subscribe to sessions() before activating, so the session delivered
            // by activate() can never race past the for-await loop.
            sharePlayStore.joinGame()
            sharePlayStore.startSharing(with: game.master.adventureTitle, image: titleImage)
        }
    }

    @MainActor
    func startProxyServer() {
        let name = model.name
        Logger.networking.debug("GameNetworkController: start proxy server \(name, privacy: .public)")
        model.masterStore?.startProxyStreaming()
    }

    @MainActor
    func startPlayerGame(to model: BrowserGameModel?) async -> Bool {
        let name = self.model.name
        Logger.networking.debug("GameNetworkController: start player game \(name, privacy: .public)")
        if let model {
            await self.model.playerStore?.toggleConnection(to: model)
            return true
        }
        if !proxy && sharePlayStore.canActivateSharePlay {
            sharePlayStore.joinGame()
            return true
        }
        return false
    }

    @MainActor
    func stopGame() async {
        let name = model.name
        Logger.networking.debug("GameNetworkController: stop game \(name, privacy: .public)")
        if await isStreaming() {
            model.masterStore?.stopStreaming()
            await model.playerStore?.stop()
            if !proxy { sharePlayStore.reset() }
        } else {
            await model.playerStore?.stop()
            if !proxy { sharePlayStore.groupSession?.leave() }
        }
        if !proxy {
            sharePlayStore.stopJoin()
            model.setLocalPlayers(to: false)
        }
        await relayAdmission.reset()
        await sharePlayPlayerJournalAdmission.reset()
        await sharePlayDeferredPeerGroupEvents.reset()
    }
}

// MARK: - Master send

extension GameNetworkController {
    /// Delivers a relayed player presentation to the co-located player
    /// controller on the game-master device. The originating message has
    /// already been fanned out to LAN and SharePlay peers, so this path must not
    /// publish it to either transport again.
    @MainActor
    func sendLocalPlayer(_ data: GameNetworkModel) async {
        guard !proxy, model.hasLocalPlayer else { return }
        await model.playerDelegate?.received(data)
    }

    @MainActor
    func sendPlayer(_ data: GameNetworkModel, to connectionId: ConnectionController.ID) async {
        let delivered = await model.masterStore?.sendResponse(data: data, id: connectionId) ?? false
        guard delivered else {
            Logger.networking.debug("GameNetworkController: Target connection \(connectionId, privacy: .public) is no longer available")
            return
        }
    }

    /// Sends a response back over the transport that carried the request. A
    /// SharePlay participant UUID is not a LAN connection UUID and must never
    /// fall through to a cross-transport broadcast.
    @MainActor
    func sendPlayer(_ data: GameNetworkModel, to origin: GameMessageOrigin) async {
        switch origin {
        case let .direct(connectionId):
            if let connectionId {
                await sendPlayer(data, to: connectionId)
            } else {
                await sendPlayer(data: data, fileJournal: data.usesFileJournal)
            }
        case let .sharePlay(participantId):
            sharePlayStore.sendData(
                data,
                fileJournal: data.usesFileJournal,
                participantId: participantId
            )
        case .file:
            // Journal callbacks do not expose the originating participant. The
            // targetId still prevents unrelated peers from applying the repair.
            sharePlayStore.sendData(data, fileJournal: data.usesFileJournal)
        case .local:
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        case let .proxy(connectionId):
            if let connectionId {
                await sendPlayer(data, to: connectionId)
            }
        }
    }

    @MainActor
    func sendPlayer(data: GameNetworkModel, fileJournal: Bool = false) async {
        await model.masterStore?.sendResponse(data: data)
        if !proxy {
            sharePlayStore.sendData(data, fileJournal: fileJournal)
            if model.hasLocalPlayer {
                await model.playerDelegate?.received(data)
            }
        }
    }

    /// Relays a host-remapped proxy presentation to every private mirror except
    /// the one that originated it. The originating mirror has already applied
    /// its own action and sending it back there would manufacture a second
    /// receipt for the same user gesture.
    @MainActor
    func sendPlayer(data: GameNetworkModel, except connectionId: ConnectionController.ID) async {
        guard proxy else { return }
        await model.masterStore?.sendResponse(data: data, except: connectionId)
    }
}

// MARK: - MasterNetworkControllerDelegate

extension GameNetworkController: MasterNetworkControllerDelegate {
    func masterLostPlayer(with connectionId: ConnectionController.ID) async {
        if proxy {
            await model.masterProxyDelegate?.lostProxy(for: connectionId)
        } else {
            await model.masterDelegate?.lostPlayer(for: connectionId)
        }
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        if proxy {
            await model.masterProxyDelegate?.readyProxy(for: connectionId)
        } else {
            await model.masterDelegate?.ready(for: .direct(connectionId))
        }
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("GameNetworkController: Master Received invalid game data from \(connectionId)")
            return
        }
        if proxy {
            // Don't resend in proxy mode — would cause an endless relay loop
            await model.masterProxyDelegate?.receivedServerProxy(gameData, connectionId: connectionId)
        } else {
            let origin = GameMessageOrigin.direct(connectionId)
            guard await model.masterDelegate?.accepts(gameData, origin: origin) == true else {
                Logger.networking.debug("GameNetworkController: Rejected unauthenticated LAN message from \(connectionId)")
                return
            }
            if Self.shouldRelayToLAN(gameData), await relayAdmission.admit(gameData) {
                await model.masterStore?.sendResponse(data: gameData, except: connectionId)
                let useFileJournal = fileJournal || gameData.usesFileJournal
                // `sendData` is itself `@MainActor` (and `@discardableResult`) — `await`
                // alone hops there, no `MainActor.run` wrapper needed.
                await sharePlayStore.sendData(gameData, fileJournal: useFileJournal)
            }
            await model.masterDelegate?.received(gameData, origin: origin)
        }
    }
}

// MARK: - Player send

extension GameNetworkController {
    @MainActor
    func sendMaster(data: GameNetworkModel, fileJournal: Bool = false) async {
        if !proxy { guard !model.hasLocalPlayer else { return } }
        await model.playerStore?.request(with: data)
        if !proxy {
            sharePlayStore.sendData(data, fileJournal: fileJournal)
        }
    }
}

// MARK: - PlayerNetworkControllerDelegate

extension GameNetworkController: PlayerNetworkControllerDelegate {
    func playerLostMaster() async {
        if proxy {
            await model.playerProxyDelegate?.lostProxyConnection()
        } else {
            await model.playerDelegate?.lostConnection()
        }
    }

    func playerReady() async {
        if proxy {
            await model.playerProxyDelegate?.readyProxy()
        } else {
            await model.playerDelegate?.ready()
        }
    }

    func playerReceived(data: Data?) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("GameNetworkController: Player received invalid game data")
            return
        }
        if proxy {
            await model.playerProxyDelegate?.receivedProxy(gameData)
        } else {
            await model.playerDelegate?.received(gameData)
        }
    }
}

// MARK: - SharePlayControllerDelegate

extension GameNetworkController: SharePlayControllerDelegate {
    @MainActor
    func handleUpdate(_ model: GameNetworkModel, id: UUID) async {
        // The messenger already yields messages in order. Await routing so that
        // order is not lost by creating one unstructured task per message.
        await routeSharePlayUpdate(model, id: id)
    }

    @MainActor
    func handleFileUpdate(_ model: GameNetworkModel) async {
        // Journal snapshots may briefly contain both an old and replacement
        // attachment. Await routing so their established order is preserved;
        // independent unstructured tasks provide no FIFO guarantee.
        await routeSharePlayFileUpdate(model)
    }

    @MainActor
    func handleFileLoadFailure(_ message: GameNetworkModel) async {
        await routeSharePlayFileUpdate(message, callbackKind: .loadFailure)
    }

    @MainActor
    func sharePlayLostPlayer(id: UUID) async {
        let lostPinnedMaster = await model.playerDelegate?
            .isPinnedSharePlayMasterParticipant(id: id) == true
        await sharePlayPlayerJournalAdmission.participantLeft(id)
        if lostPinnedMaster {
            await sharePlayDeferredPeerGroupEvents.reset()
        } else {
            await sharePlayDeferredPeerGroupEvents.participantLeft(id)
        }
        await model.masterDelegate?.lostPlayer(for: id)
        await model.playerDelegate?.sharePlayParticipantLeft(id: id)
    }

    @MainActor
    func sharePlayLostConnection() async {
        await sharePlayPlayerJournalAdmission.reset()
        await sharePlayDeferredPeerGroupEvents.reset()
        await model.playerDelegate?.lostConnection()
    }

    @MainActor
    func sharePlaySessionConfigured() async {
        await sharePlayPlayerJournalAdmission.reset()
        await sharePlayDeferredPeerGroupEvents.reset()
        guard !model.hasLocalPlayer else { return }
        // Keep ready() in the GroupSession state loop. If list reporting
        // suspends, invalidation cannot overtake it and then be clobbered by
        // the obsolete ready operation resuming afterward.
        await model.playerDelegate?.ready()
    }

    @MainActor
    func sharePlayJoinedPlayer(id: UUID) async {
        // `id` is a GroupActivities transport participant, not the player's
        // later in-game sender ID. Preserve that origin so replay is physically
        // addressed through Messenger and can never fall through to Bonjour.
        await model.masterDelegate?.ready(for: .sharePlay(id))
        if model.masterDelegate != nil {
            // The master reference above is first in the targeted Messenger
            // queue, establishing roster/authority before a retained
            // player-authored attachment can be released. Existing Journal
            // bytes then need only their original sender/message/digest
            // admission, not another upload.
            _ = sharePlayStore.reannounceCurrentJournalAdmissions(to: id)
        }
    }

    @MainActor
    func routeSharePlayUpdate(_ message: GameNetworkModel, id: UUID) async {
        await routeSharePlayUpdate(
            message,
            id: id,
            allowsUnknownRosterDeferral: true
        )
    }

    @MainActor
    private func routeSharePlayUpdate(
        _ message: GameNetworkModel,
        id: UUID,
        allowsUnknownRosterDeferral: Bool
    ) async {
        let origin = GameMessageOrigin.sharePlay(id)
        // GroupSessionMessenger does not echo this device's own sends. On the
        // game-master device, authoritative messages reach the co-located
        // PlayerController through sendPlayer/sendLocalPlayer instead. Therefore
        // any inbound peer envelope claiming to be the master is necessarily a
        // forged logical identity and must not get the first physical binding.
        if message.sender.isMaster, model.hasLocalPlayer {
            Logger.networking.debug("GameNetworkController: Rejected inbound SharePlay master message on the game-master device")
            return
        }
        if message.sender.isMaster,
           let playerDelegate = model.playerDelegate,
           await !playerDelegate.isLocalSharePlayTarget(message.targetId) {
            Logger.networking.debug("GameNetworkController: Ignored master message addressed to another SharePlay player")
            return
        }
        if !message.sender.isMaster {
            guard message.sender.role == .player else {
                Logger.networking.debug("GameNetworkController: Rejected local-only role on SharePlay from \(id)")
                return
            }

            // On the game-master device, MasterController owns the roster and
            // transport binding. Do not mutate the Journal admission state
            // until that authoritative check succeeds, or a forged first
            // packet could poison the actor and deny the real participant.
            if let masterDelegate = model.masterDelegate {
                guard await masterDelegate.accepts(message, origin: origin) else {
                    Logger.networking.debug("GameNetworkController: Rejected unauthenticated SharePlay message from \(id)")
                    return
                }
            } else {
                let isAdmissionRelayedByPinnedMaster: Bool
                if message.isPlayerJournalAdmissionMetadata {
                    isAdmissionRelayedByPinnedMaster = await sharePlayPlayerJournalAdmission.isTrustedMasterRelay(
                        participantID: id
                    )
                } else {
                    isAdmissionRelayedByPinnedMaster = false
                }
                if !isAdmissionRelayedByPinnedMaster {
                    guard let playerDelegate = model.playerDelegate else {
                        Logger.networking.debug("GameNetworkController: Rejected player envelope before SharePlay sender binding")
                        return
                    }
                    let acceptsPeer = await playerDelegate.acceptsSharePlayPeerMessage(
                        message,
                        participantId: id
                    )
                    if !acceptsPeer {
                        let shouldDefer: Bool
                        if allowsUnknownRosterDeferral {
                            shouldDefer = await playerDelegate.shouldDeferSharePlayPeerGroupEvent(
                                message,
                                participantId: id
                            )
                        } else {
                            shouldDefer = false
                        }
                        if shouldDefer {
                            if await sharePlayDeferredPeerGroupEvents.retain(
                                message,
                                participantID: id
                            ) {
                                Logger.networking.debug("GameNetworkController: Deferred player Group event until the next master roster update")
                            } else {
                                Logger.networking.debug("GameNetworkController: Rejected player Group event because the pre-roster deferral is full")
                            }
                            return
                        }
                        Logger.networking.debug("GameNetworkController: Rejected player envelope before SharePlay sender binding")
                        return
                    }
                }
            }
            guard await sharePlayPlayerJournalAdmission.acceptsPlayerMessenger(
                message,
                participantID: id
            ) else {
                Logger.networking.debug("GameNetworkController: Rejected rebound SharePlay sender from \(id)")
                return
            }
        }

        if message.isJournalAdmissionOnly {
            if message.sender.isMaster {
                // A master admission packet is deliberately side-effect free:
                // only a previously authenticated master participant may bind
                // the anonymous attachment. A complete first master envelope
                // may pin session authority, but never enters repair or
                // presentation handlers itself.
                guard let playerDelegate = model.playerDelegate,
                      await playerDelegate.acceptsSharePlayMasterJournalAdmission(
                          message,
                          participantId: id
                      ),
                      await playerDelegate.isPinnedSharePlayMasterParticipant(id: id),
                      await sharePlayPlayerJournalAdmission.trustMasterRelay(
                          participantID: id
                      )
                else {
                    Logger.networking.debug("GameNetworkController: Rejected Journal admission from an unpinned SharePlay master")
                    return
                }
            }

            let admission = await sharePlayPlayerJournalAdmission.admitAnnouncement(
                message,
                participantID: id
            )
            let deferredJournals: [SharePlayDeferredJournalCallback]
            switch admission {
            case .admitted(let callbacks):
                deferredJournals = callbacks
            case .notAdmission, .rejected:
                Logger.networking.debug("GameNetworkController: Rejected conflicting or malformed Journal admission metadata")
                return
            }

            // Journal may surface the attachment before Messenger delivers its
            // participant-attributed control packet. Release only the exact
            // deferred fingerprint, and never route the control packet itself.
            for deferredJournal in deferredJournals {
                await routeSharePlayFileUpdate(
                    deferredJournal.model,
                    callbackKind: deferredJournal.kind
                )
            }
            return
        }

        if message.sender.isMaster {
            await model.playerDelegate?.receivedSharePlay(message, participantId: id)
            let isPinnedMaster = await model.playerDelegate?
                .isPinnedSharePlayMasterParticipant(id: id) == true
            if isPinnedMaster {
                _ = await sharePlayPlayerJournalAdmission.trustMasterRelay(
                    participantID: id
                )
            }
            if isPinnedMaster,
               let playerDelegate = model.playerDelegate,
               await playerDelegate.didAcceptSharePlayMasterState(
                   message,
                   participantId: id
               ) {
                let deferredEvents = await sharePlayDeferredPeerGroupEvents.drain()
                for deferredEvent in deferredEvents {
                    // One roster update is the complete waiting window. Every
                    // event now takes the ordinary authority and physical
                    // sender-binding path and can never be deferred again.
                    await routeSharePlayUpdate(
                        deferredEvent.model,
                        id: deferredEvent.participantID,
                        allowsUnknownRosterDeferral: false
                    )
                }
            }
        } else {
            // Match the LAN-ingress ordering: once the physical SharePlay
            // sender is authenticated, peer-visible player intent must cross
            // the bridge before the master canonicalizes it. Otherwise a
            // mismatched Photo/PDF/Space reveal can make the master broadcast
            // its canonical asset first and then leave LAN peers displaying
            // the stale raw player event that is relayed afterward.
            if model.hasLocalPlayer,
               Self.shouldRelayToLAN(message),
               await relayAdmission.admit(message) {
                await model.masterStore?.sendResponse(data: message)
            }
            await model.masterDelegate?.received(message, origin: origin)
            if !model.hasLocalPlayer, Self.shouldRelayToLAN(message) {
                await model.playerDelegate?.receivedSharePlay(message, participantId: id)
            }
        }
    }

    @MainActor
    func routeSharePlayFileUpdate(
        _ message: GameNetworkModel,
        callbackKind: SharePlayJournalCallbackKind = .update
    ) async {
        // Journal snapshots can include locally published attachments, but the
        // master already delivered those to its local player at send time. Do
        // not let either a duplicate snapshot or a peer-forged master envelope
        // enter the local player's authority path.
        if message.sender.isMaster, model.hasLocalPlayer {
            Logger.networking.debug("GameNetworkController: Rejected inbound SharePlay master file message on the game-master device")
            return
        }
        if message.sender.isMaster,
           let playerDelegate = model.playerDelegate,
           await !playerDelegate.isLocalSharePlayTarget(message.targetId) {
            Logger.networking.debug("GameNetworkController: Ignored Journal repair addressed to another SharePlay player")
            return
        }
        switch await sharePlayPlayerJournalAdmission.disposition(
            forJournal: message,
            callbackKind: callbackKind
        ) {
        case .authorized:
            break
        case .deferred:
            Logger.networking.debug("GameNetworkController: Deferred Journal message until its SharePlay announcement")
            return
        case .rejected:
            Logger.networking.debug("GameNetworkController: Rejected uncorrelated SharePlay file message")
            return
        }
        if !message.sender.isMaster,
           let masterDelegate = model.masterDelegate,
           await !masterDelegate.accepts(message, origin: .file) {
            Logger.networking.debug("GameNetworkController: Rejected unauthenticated SharePlay file message")
            return
        }
        sharePlayStore.markJournalAttachmentAuthenticated(message)

        if message.sender.isMaster {
            switch callbackKind {
            case .update:
                await model.playerDelegate?.receivedSharePlayFile(message)
            case .loadFailure:
                await model.playerDelegate?.sharePlayFileLoadFailed(message)
            }
        } else {
            // Journal delivery uses the same bridge ordering as Messenger.
            // `shouldRelayToLAN` still excludes Character synchronization,
            // reports, acknowledgements, and repair requests.
            if model.hasLocalPlayer,
               Self.shouldRelayToLAN(message),
               await relayAdmission.admit(message) {
                await model.masterStore?.sendResponse(data: message)
            }
            await model.masterDelegate?.receivedFile(message)
            if !model.hasLocalPlayer, Self.shouldRelayToLAN(message) {
                await model.playerDelegate?.receivedSharePlayFile(message)
            }
        }
    }
}

// MARK: - Utility

extension GameNetworkController {
    func isStreaming() async -> Bool {
        await model.masterStore?.networkModel.isStreaming ?? false
    }

    @MainActor
    func resetName(name: String, supporterTier: SupporterTier = .none) {
        model.masterStore?.networkModel.name = name
        model.masterStore?.networkModel.supporterTier = supporterTier
        model.playerStore?.networkModel.name = name
        model.playerStore?.networkModel.supporterTier = supporterTier
    }

}
