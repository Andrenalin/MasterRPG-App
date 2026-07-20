// @copyright André Trettin

import CoreRPG
import CryptoKit
import Foundation

/// Sender identity — travels with every message. Players send only this;
/// receivers never derive the sender from a roster lookup again.
struct GameSenderModel: Equatable, Codable, Sendable {
    var id: UUID
    var role: GameType
    var name: String
    var characterId: UUID?

    var isMaster: Bool { role == .master }

    var playerModel: PlayerGameModel {
        PlayerGameModel(id: id, type: role, name: name, characterId: characterId)
    }
}

/// The master-authoritative block. Only master messages carry it — a player
/// message structurally cannot change roster, controls, or features.
struct GameMasterStateModel: Equatable, Codable, Sendable {
    var state: GameState
    var adventureId: UUID?
    var adventureTitle: String?
    var players: [PlayerGameModel] = []
    var controls: [SharingControlModel] = []
    var features: GameFeatureModel = GameFeatureModel()
}

/// The logical recipient set is independent from the physical transport.
/// SharePlay may still deliver a master-only message to the whole session, but
/// peers can reject it before running any module handler and a LAN bridge must
/// never fan it out.
enum GameMessageAudience: Int, Codable, Hashable, Sendable {
    /// Used only when decoding an older envelope that did not carry an audience.
    case automatic = 0
    case master = 1
    case group = 2
    case target = 3
}

/// Separates a user action from a request for missing bytes. Historically both
/// used a data-less reveal/store, which made a proxy host swallow presentations
/// as if they were local cache repairs.
enum GameMessagePurpose: Int, Codable, Hashable, Sendable {
    /// Used only for envelopes produced before `purpose` was introduced.
    case legacy = 0
    case event = 1
    case assetRequest = 2
}

struct GameNetworkModel: Codable, Sendable {
    /// Wire format generations:
    /// - 1: shipped 2.6 app — players/controls/features travel inside
    ///      `gameConfig` (`GameNetworkModelV1`).
    /// - 2: explicit `sender` + master-only `masterState` + optional `targetId`.
    ///      Unreleased dev layouts (gameConfig + gameRoster [+ gameControl]) also
    ///      stamped 1 or 2 and are decoded via the legacy fallbacks.
    /// Current in-memory schema. Encoded messages still advertise the V1 wire
    /// version because the encoder emits a compatibility superset for old peers.
    static let currentVersion = 2

    var version: Int = GameNetworkModel.currentVersion
    /// Stable identity for one logical send. Transport retries and bridge copies
    /// retain this value, allowing admission and delivery receipts to correlate
    /// without relying on independent per-device counters.
    var messageID: UUID?
    /// The master message answered by this acknowledgement or asset request.
    /// Ordinary player events leave it nil.
    var replyToMessageID: UUID?
    /// Wall-clock intent time used only by last-wins peer events. Counter ordering
    /// remains the compatibility fallback for envelopes produced by older peers.
    var timestamp: TimeInterval
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var masterId: UUID
    var sender: GameSenderModel
    /// Present only in master messages.
    var masterState: GameMasterStateModel?
    /// When set, only the addressed participant processes the message —
    /// responses to a data request no longer flip everyone's screen.
    var targetId: UUID?
    var audience: GameMessageAudience
    var purpose: GameMessagePurpose
    /// Control-plane Messenger packet that authenticates a later anonymous
    /// GroupSessionJournal attachment. `nil` is the backwards-compatible wire
    /// value for every real presentation, including attachment-reuse events.
    var journalAdmissionOnly: Bool?
    /// SHA-256 of the raw GroupSessionJournal attachment. The physically
    /// attributed Messenger admission carries this value, binding otherwise
    /// anonymous Journal bytes to the participant that announced them.
    var journalPayloadDigest: Data?
    var data: NetworkCodableDataType

    init(
        version: Int = GameNetworkModel.currentVersion,
        messageID: UUID? = UUID(),
        replyToMessageID: UUID? = nil,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        counter: Int,
        proxyCounter: Int,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        masterId: UUID,
        sender: GameSenderModel,
        masterState: GameMasterStateModel? = nil,
        targetId: UUID? = nil,
        audience: GameMessageAudience = .automatic,
        purpose: GameMessagePurpose = .event,
        journalAdmissionOnly: Bool? = nil,
        journalPayloadDigest: Data? = nil,
        data: NetworkCodableDataType
    ) {
        self.version = version
        self.messageID = messageID
        self.replyToMessageID = replyToMessageID
        self.timestamp = timestamp
        self.counter = counter
        self.proxyCounter = proxyCounter
        self.type = type
        self.subType = subType
        self.masterId = masterId
        self.sender = sender
        self.masterState = masterState
        self.targetId = targetId
        self.audience = audience
        self.purpose = purpose
        self.journalAdmissionOnly = journalAdmissionOnly
        self.journalPayloadDigest = journalPayloadDigest
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case version
        case messageID
        case replyToMessageID
        case timestamp
        case counter
        case proxyCounter
        case type
        case subType
        case masterId
        case sender
        case masterState
        case targetId
        case audience
        case purpose
        case journalAdmissionOnly
        case journalPayloadDigest
        case data
        // legacy layouts and compatibility superset
        case gameConfig
        case gameRoster
        case gameControl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        messageID = try container.decodeIfPresent(UUID.self, forKey: .messageID)
        replyToMessageID = try container.decodeIfPresent(UUID.self, forKey: .replyToMessageID)
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
        counter = try container.decode(Int.self, forKey: .counter)
        proxyCounter = try container.decode(Int.self, forKey: .proxyCounter)
        type = try container.decode(RPGMessageType.self, forKey: .type)
        subType = try container.decode(RPGMessageActionType.self, forKey: .subType)
        targetId = try container.decodeIfPresent(UUID.self, forKey: .targetId)
        audience = try container.decodeIfPresent(GameMessageAudience.self, forKey: .audience) ?? .automatic
        purpose = try container.decodeIfPresent(GameMessagePurpose.self, forKey: .purpose) ?? .legacy
        journalAdmissionOnly = try container.decodeIfPresent(Bool.self, forKey: .journalAdmissionOnly)
        journalPayloadDigest = try container.decodeIfPresent(Data.self, forKey: .journalPayloadDigest)
        data = try container.decode(NetworkCodableDataType.self, forKey: .data)

        if let sender = try container.decodeIfPresent(GameSenderModel.self, forKey: .sender) {
            self.sender = sender
            masterId = try container.decode(UUID.self, forKey: .masterId)
            masterState = try container.decodeIfPresent(GameMasterStateModel.self, forKey: .masterState)
            return
        }

        // Pure V1 envelope (shipped 2.6): no gameRoster/gameControl keys —
        // everything travels inside gameConfig.
        if !container.contains(.gameRoster), !container.contains(.gameControl),
           let v1Config = try? container.decode(GameConfigModelV1.self, forKey: .gameConfig) {
            (masterId, sender, masterState) = Self.identity(
                config: GameConfigModel(id: v1Config.id, state: v1Config.state, master: v1Config.master),
                players: v1Config.players,
                controls: v1Config.controls,
                features: v1Config.features
            )
            return
        }

        // Unreleased dev layouts: slim gameConfig plus gameRoster [+ gameControl].
        let config = try container.decode(GameConfigModel.self, forKey: .gameConfig)
        let roster = try container.decodeIfPresent(GameRosterModel.self, forKey: .gameRoster) ?? .empty
        let control = try container.decodeIfPresent(GameControlModel.self, forKey: .gameControl)
            ?? container.decodeIfPresent(LegacyGameControlModel.self, forKey: .gameRoster)?.gameControl
            ?? .empty
        (masterId, sender, masterState) = Self.identity(
            config: config,
            players: roster.players,
            controls: control.controls,
            features: control.features
        )
    }

    /// Compatibility superset: every peer generation decodes the same bytes.
    /// V1 peers (shipped 2.6) read players/controls/features from inside
    /// `gameConfig` via the down-mapper; the unreleased dev layouts read
    /// `gameConfig` + `gameRoster`/`gameControl`; current peers read
    /// `sender`/`masterState`. The version key stays at V1 so old clients do not
    /// reject an otherwise compatible envelope.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(GameNetworkModelV1.wireVersion, forKey: .version)
        try container.encodeIfPresent(messageID, forKey: .messageID)
        try container.encodeIfPresent(replyToMessageID, forKey: .replyToMessageID)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(counter, forKey: .counter)
        try container.encode(proxyCounter, forKey: .proxyCounter)
        try container.encode(type, forKey: .type)
        try container.encode(subType, forKey: .subType)
        try container.encode(masterId, forKey: .masterId)
        try container.encode(sender, forKey: .sender)
        try container.encodeIfPresent(masterState, forKey: .masterState)
        try container.encodeIfPresent(targetId, forKey: .targetId)
        try container.encode(audience, forKey: .audience)
        try container.encode(purpose, forKey: .purpose)
        try container.encodeIfPresent(journalAdmissionOnly, forKey: .journalAdmissionOnly)
        try container.encodeIfPresent(journalPayloadDigest, forKey: .journalPayloadDigest)
        let configV1 = v1Model.gameConfig
        try container.encode(configV1, forKey: .gameConfig)
        try container.encode(GameRosterSuperset(players: configV1.players, controls: configV1.controls, features: configV1.features), forKey: .gameRoster)
        try container.encode(GameControlModel(controls: configV1.controls, features: configV1.features), forKey: .gameControl)
        try container.encode(data, forKey: .data)
    }

    nonisolated static func journalDigest(for payload: Data) -> Data {
        Data(SHA256.hash(data: payload))
    }

    var resolvedJournalPayloadDigest: Data? {
        if let payload = data.data {
            return Self.journalDigest(for: payload)
        }
        return journalPayloadDigest
    }

    /// Compares the immutable control-plane identity while binding a full
    /// callback to the digest recomputed from its loaded bytes. Admission-only
    /// is deliberately excluded because the Messenger half is marked and the
    /// real Journal metadata is not.
    func hasSameJournalFingerprint(as other: GameNetworkModel) -> Bool {
        version == other.version &&
            replyToMessageID == other.replyToMessageID &&
            masterId == other.masterId &&
            sender == other.sender &&
            masterState == other.masterState &&
            counter == other.counter &&
            proxyCounter == other.proxyCounter &&
            type == other.type &&
            subType == other.subType &&
            audience == other.audience &&
            purpose == other.purpose &&
            targetId == other.targetId &&
            data.id == other.data.id &&
            data.type == other.data.type &&
            data.version == other.data.version &&
            data.assetVersion == other.data.assetVersion &&
            data.contentVersion == other.data.contentVersion &&
            timestamp == other.timestamp &&
            resolvedJournalPayloadDigest == other.resolvedJournalPayloadDigest
    }

    /// Derives sender identity and master state from a legacy config + roster.
    private static func identity(
        config: GameConfigModel,
        players: [PlayerGameModel],
        controls: [SharingControlModel],
        features: GameFeatureModel
    ) -> (masterId: UUID, sender: GameSenderModel, masterState: GameMasterStateModel?) {
        if config.isMaster {
            let sender = GameSenderModel(id: config.id, role: .master, name: config.master.name, characterId: nil)
            let state = GameMasterStateModel(
                state: config.state,
                adventureId: config.master.adventureId,
                adventureTitle: config.master.adventureTitle,
                players: players,
                controls: controls,
                features: features
            )
            return (config.master.id, sender, state)
        }
        let player = players.first(where: { $0.id == config.id })
        let role: GameType = if let type = player?.type, type != .notSet {
            type
        } else {
            .player
        }
        let name = if let playerName = player?.name, !playerName.isEmpty {
            playerName
        } else {
            "Player \(config.id.uuidString.prefix(8))"
        }
        let sender = GameSenderModel(id: config.id, role: role, name: name, characterId: player?.characterId)
        return (config.master.id, sender, nil)
    }
}

extension GameNetworkModel {
    /// Bounds wall-clock ordering input before it can become the presentation
    /// baseline. Legacy envelopes use zero; current envelopes must carry a
    /// finite positive time that is not implausibly ahead of this device.
    static let maximumFutureEventTimestampSkew: TimeInterval = 300

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

// MARK: - V1 wire format (shipped 2.6 app)

/// The envelope exactly as the first release sends and expects it: roster,
/// sharing controls and feature gates travel inside `gameConfig`. Restored so
/// old and new app versions can play in the same game.
struct GameNetworkModelV1: Codable, Sendable {
    static let wireVersion = 1

    var version: Int = GameNetworkModelV1.wireVersion
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var gameConfig: GameConfigModelV1
    var data: NetworkCodableDataType
}

/// V1 shape of `GameConfigModel` — identity plus the embedded roster/control
/// state that the current envelope splits into `sender`/`masterState`.
struct GameConfigModelV1: Equatable, Codable, Sendable {
    var id: UUID
    var state: GameState
    var master: MasterGameModel
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
}

extension GameNetworkModelV1 {
    /// Up-map V1 → V2. Keeps `version` at 1 so receivers can tell the peer is old.
    var v2Model: GameNetworkModel {
        let config = GameConfigModel(id: gameConfig.id, state: gameConfig.state, master: gameConfig.master)
        let identity = GameNetworkModel.legacyIdentity(
            config: config,
            players: gameConfig.players,
            controls: gameConfig.controls,
            features: gameConfig.features
        )
        return GameNetworkModel(
            version: version,
            messageID: nil,
            timestamp: 0,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            masterId: identity.masterId,
            sender: identity.sender,
            masterState: identity.masterState,
            audience: .automatic,
            purpose: .legacy,
            data: data
        )
    }
}

extension GameNetworkModel {
    /// Down-map V2 → V1: embed the state back into `gameConfig` the way the
    /// shipped 2.6 app expects it. Player messages carry the sender as the only
    /// roster entry so V1 peers can still resolve the sender name.
    var v1Model: GameNetworkModelV1 {
        let master = MasterGameModel(
            id: masterId,
            type: .master,
            name: sender.isMaster ? sender.name : "",
            adventureId: masterState?.adventureId,
            adventureTitle: masterState?.adventureTitle
        )
        let players = masterState?.players ?? (sender.isMaster ? [] : [sender.playerModel])
        return GameNetworkModelV1(
            version: 1,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            gameConfig: GameConfigModelV1(
                id: sender.id,
                state: masterState?.state ?? .started,
                master: master,
                players: players,
                controls: masterState?.controls ?? [],
                features: masterState?.features ?? GameFeatureModel()
            ),
            data: data
        )
    }

    static func legacyIdentity(
        config: GameConfigModel,
        players: [PlayerGameModel],
        controls: [SharingControlModel],
        features: GameFeatureModel
    ) -> (masterId: UUID, sender: GameSenderModel, masterState: GameMasterStateModel?) {
        identity(config: config, players: players, controls: controls, features: features)
    }
}

/// Encode-only shape for the `gameRoster` key: the intermediate dev layout
/// required controls/features inside gameRoster, the later dev layout only
/// reads players — the superset satisfies both decoders.
private struct GameRosterSuperset: Encodable {
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
}

private struct LegacyGameControlModel: Decodable {
    var controls: [SharingControlModel] = []
    var features: GameFeatureModel = GameFeatureModel()

    var gameControl: GameControlModel {
        GameControlModel(controls: controls, features: features)
    }

    enum CodingKeys: String, CodingKey {
        case controls
        case features
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        controls = try container.decodeIfPresent([SharingControlModel].self, forKey: .controls) ?? []
        features = try container.decodeIfPresent(GameFeatureModel.self, forKey: .features) ?? GameFeatureModel()
    }
}

enum GameMessageOrigin: Hashable, Sendable {
    case direct(ConnectionController.ID?)
    case proxy(ConnectionController.ID?)
    case sharePlay(UUID)
    case file
    case local

    var connectionId: ConnectionController.ID? {
        switch self {
        case let .direct(connectionId), let .proxy(connectionId):
            connectionId
        case .sharePlay, .file, .local:
            nil
        }
    }

    var sharePlayParticipantId: UUID? {
        guard case let .sharePlay(participantId) = self else { return nil }
        return participantId
    }

    /// Identity used only to associate a transport peer with its game player so
    /// disconnect cleanup works for both Bonjour and SharePlay. It must not be
    /// reused as a physical response route.
    var participantConnectionId: UUID? {
        switch self {
        case let .direct(connectionId), let .proxy(connectionId):
            connectionId
        case let .sharePlay(participantId):
            participantId
        case .file, .local:
            nil
        }
    }

    var isProxy: Bool {
        guard case .proxy = self else { return false }
        return true
    }

    var usesSharePlayFileTransport: Bool {
        switch self {
        case .sharePlay, .file:
            true
        case .direct, .proxy, .local:
            false
        }
    }
}

struct GameMessageKey: Hashable, Sendable {
    let messageID: UUID?
    let senderId: UUID
    let counter: Int
    let proxyCounter: Int
    let type: RPGMessageType
    let subType: RPGMessageActionType
    let dataId: UUID
    let dataType: NetworkModules
    let dataVersion: Int
    let purpose: GameMessagePurpose
    /// A metadata-only delivery (failed journal transfer) and the later full
    /// payload share every other field — payload presence keeps the real bytes
    /// from being dropped as a duplicate.
    let hasData: Bool

    init(model: GameNetworkModel) {
        messageID = model.messageID
        senderId = model.sender.id
        counter = model.counter
        proxyCounter = model.proxyCounter
        type = model.type
        subType = model.subType
        dataId = model.data.id
        dataType = model.data.type
        dataVersion = model.data.version
        purpose = model.purpose
        hasData = model.data.data != nil
    }
}

struct GameMessageEvent: Sendable {
    let model: GameNetworkModel
    let origin: GameMessageOrigin

    var connectionId: ConnectionController.ID? {
        origin.connectionId
    }

    var fromProxy: Bool {
        origin.isProxy
    }

    var deduplicationKey: GameMessageKey? {
        guard model.subType != .ok,
              model.subType != .failed
        else { return nil }
        guard model.messageID != nil || model.counter > 0 else { return nil }
        return GameMessageKey(model: model)
    }
}

actor GameMessagePipeline {
    private let recentLimit: Int
    private var messages: [GameMessageEvent] = []
    private var processing = false
    private var isCancelled = false
    private var recentKeys: [GameMessageKey] = []
    private var recentKeySet: Set<GameMessageKey> = []
    private var pendingKeySet: Set<GameMessageKey> = []
    private var currentKey: GameMessageKey?

    init(recentLimit: Int = 256) {
        self.recentLimit = recentLimit
    }

    func enqueue(_ event: GameMessageEvent) -> Bool {
        guard !isCancelled else { return false }
        if let key = event.deduplicationKey {
            guard !recentKeySet.contains(key), !pendingKeySet.contains(key) else { return false }
            pendingKeySet.insert(key)
        }
        messages.append(event)
        return true
    }

    func next() -> GameMessageEvent? {
        guard !isCancelled, !processing, !messages.isEmpty else { return nil }
        processing = true
        let event = messages.removeFirst()
        currentKey = event.deduplicationKey
        return event
    }

    func processed(success: Bool) {
        if let currentKey {
            pendingKeySet.remove(currentKey)
            if success {
                remember(currentKey)
            }
        }
        currentKey = nil
        processing = false
    }

    func cancelAll() {
        messages.removeAll()
        processing = false
        isCancelled = true
        recentKeys.removeAll()
        recentKeySet.removeAll()
        pendingKeySet.removeAll()
        currentKey = nil
    }

    func reset() {
        messages.removeAll()
        processing = false
        isCancelled = false
        recentKeys.removeAll()
        recentKeySet.removeAll()
        pendingKeySet.removeAll()
        currentKey = nil
    }

    private func remember(_ key: GameMessageKey) {
        recentKeys.append(key)
        recentKeySet.insert(key)

        while recentKeys.count > recentLimit {
            let removed = recentKeys.removeFirst()
            recentKeySet.remove(removed)
        }
    }
}

extension GameNetworkModel: CustomDebugStringConvertible {
    var debugDescription: String {
        "counter \(counter) type: \(type) - \(subType), game: \(sender.name) data: \(data.id) \(data.type.token)"
    }
}

extension GameNetworkModel {
    var senderType: GameType { sender.role }
    var senderName: String { sender.name }
}

extension GameNetworkModel: MessageMapper {
    static func decodeData(of data: Data?) -> GameNetworkModel? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(GameNetworkModel.self, from: data)
        } catch {
            print("**** Error \(error.localizedDescription)")
        }
        return nil
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        // NetworkCodableDataType stores file bytes as Base64. Escaping every
        // slash can nearly double valid Base64 output and unnecessarily halves
        // the Messenger fallback limit. All supported decoders accept literal
        // JSON slashes, so keep the canonical payload compact.
        encoder.outputFormatting = .withoutEscapingSlashes
        return try? encoder.encode(self)
    }
}
