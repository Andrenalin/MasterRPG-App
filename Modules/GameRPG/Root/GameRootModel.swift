// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Combine
import DiceRPG
import Foundation
import GroupActivities
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG


@MainActor @Observable
final class GameRootModel: Sendable {
    private struct ValueUpdateKey: Hashable {
        let senderId: UUID
        let characterId: UUID
        let entryId: UUID
    }

    var gameConfig: GameConfigModel = .empty
    var gameRoster: GameRosterModel = .empty
    var gameControl: GameControlModel = .empty
    /// The players who shared a dice roll from a device without the 3D table, by the name the
    /// dice overlay lists the roll under. The table shows their dice at its guest seat.
    var tableGuestNames: Set<String> = []

    var startGameTime = Date()

    var selectedCharacter: UUID?
    var selectedGameMaster: UUID?
    public var selectedAdventure: UUID?

    var playerGameStarted: Bool = false

    var logData: [Int: LogGameModel] = [:]
    var logs: [Int] = []
    var generatedValueEntry: ValueEntryModel?
    var attachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
    var metaDataAttachments: [NetworkModules: UUID] = [:]
    // Keyed off `counter` (monotonic per sender), not wall-clock `timestamp`:
    // two legitimate, back-to-back edits from the same player can share an
    // identical or non-increasing `Date.now` timestamp (clock coalescing, or
    // a system clock adjustment), which previously made the second one fail
    // this gate and be silently dropped. See CODE_AUDIT_Network §5.17.
    private var latestValueUpdateCounters: [ValueUpdateKey: Int] = [:]
    /// Items each player's Character packages introduced to this device, per sender. A
    /// package may only overwrite items that are its own primary item, are listed here or
    /// are new — see `PeerImportPolicy` / CODE_AUDIT_15 §5.2.
    private var peerIntroducedItemIds: [UUID: Set<UUID>] = [:]
    private var latestValueUpdateOrder: [ValueUpdateKey] = []
    private static let maximumRetainedValueUpdateCounters = 512

    var masterController: MasterController?
    var playerController: PlayerController?

    #if !os(tvOS)
    var gameTableModel: GameTableModel?
    #endif

    #if os(visionOS)
    var shareState = GameShareStateModel()

    /// True only while an actual SharePlay `GroupSession` is active — see
    /// `EnvironmentValues.isSpaceSharePlayActive`, which this backs.
    public var isSharePlayActive: Bool { shareState.isSharePlayActive }
    #endif

    /// Longest a peer-controlled player name is allowed to be. An authenticated peer
    /// can otherwise send a name up to the frame limit, which is then echoed in every
    /// master broadcast (the v1-compatible encoder writes the roster three times per
    /// message) and persisted per statistics event. See CODE_AUDIT_17 §6.9.
    static let maxPlayerNameLength = GameSenderModel.maxNameLength

    func add(playerId: UUID, playerModel: PlayerGameModel, sharingModel: SharingControlModel) -> Bool {
        // A claimed player model whose id doesn't match the sender is a failed
        // roster lookup (PlayerGameModel.empty carries a random id) — writing it
        // would orphan the roster entry and lose the player's name for good.
        guard playerModel.id == playerId else { return false }

        var playerModel = playerModel
        if playerModel.name.count > Self.maxPlayerNameLength {
            playerModel.name = String(playerModel.name.prefix(Self.maxPlayerNameLength))
        }

        let isNewPlayer: Bool
        if let index = gameRoster.players.firstIndex(where: { $0.id == playerId }) {
            // `characterId` travels on every message as sender-declared,
            // otherwise-untrusted input — this runs for every inbound
            // message, not just the join handshake, so overwriting it here
            // let any later message silently reassign which Character a
            // roster entry claims. Once set, preserve it; only a still-nil
            // slot may be claimed. See CODE_AUDIT_Game §6.1.
            var updated = playerModel
            if let ownedCharacterId = gameRoster.players[index].characterId {
                updated.characterId = ownedCharacterId
            }
            gameRoster.players[index] = updated
            isNewPlayer = false
        } else {
            gameRoster.players.append(playerModel)
            isNewPlayer = true
        }

        // Controls are matched by id, never by roster index — the sharing UI can
        // reorder or replace the controls list independently of the roster.
        var model = sharingModel
        if let index = gameControl.controls.firstIndex(where: { $0.id == playerId }) {
            model.show = gameControl.controls[index].show
            gameControl.controls[index] = model
        } else {
            gameControl.controls.append(model)
        }
        return isNewPlayer
    }

    func add(playerId: UUID, sharingModel: SharingControlModel) {
        if let index = gameControl.controls.firstIndex(where: { $0.id == playerId }) {
            gameControl.controls[index] = sharingModel
        } else {
            gameControl.controls.append(sharingModel)
        }
    }

    func remove(playerId: UUID) -> Bool {
        guard let index = gameRoster.players.firstIndex(where: { $0.id == playerId }) else { return false }
        gameRoster.players.remove(at: index)
        if let controlIndex = gameControl.controls.firstIndex(where: { $0.id == playerId }) {
            gameControl.controls.remove(at: controlIndex)
        }
        return true
    }

    func reset(gameConfig: GameConfigModel, gameRoster: GameRosterModel = .empty, gameControl: GameControlModel = .empty) {
        self.gameConfig = gameConfig
        self.gameRoster = gameRoster
        self.gameControl = gameControl
        latestValueUpdateCounters = [:]
        peerIntroducedItemIds = [:]
    }

    func reset(master: MasterGameModel) {
        gameConfig.master = master
    }

    /// Applies a master broadcast in one atomic step so concurrent readers
    /// (message building, sendCharacter) never observe a half-updated state.
    func applyMasterBroadcast(
        masterId: UUID,
        masterName: String,
        supporterTier: SupporterTier = .none,
        state: GameMasterStateModel
    ) {
        gameConfig.master = MasterGameModel(
            id: masterId,
            type: .master,
            name: masterName,
            adventureId: state.adventureId,
            adventureTitle: state.adventureTitle,
            supporterTier: supporterTier
        )
        gameControl.controls = state.controls
        gameControl.features = state.features

        let localPlayer = gamePlayer
        var updatedPlayers = state.players
        if let localIndex = updatedPlayers.firstIndex(where: { $0.id == gameConfig.id }),
           localPlayer.id == gameConfig.id {
            // The local entitlement is authoritative for this device. An older
            // master can legitimately send a roster entry without supporter data.
            updatedPlayers[localIndex].supporterTier = localPlayer.supporterTier
        } else if localPlayer.id == gameConfig.id {
            // Keep the local player in the roster, but never append the `.empty`
            // fallback — its random id would poison every later lookup.
            updatedPlayers.append(localPlayer)
        }
        gameRoster.players = updatedPlayers
    }

    /// Builds an outgoing message from local state in one MainActor hop, so a
    /// message never carries a torn combination from a concurrent update.
    /// Master messages carry the authoritative `masterState`; player messages
    /// carry only the sender identity.
    func outgoingMessage(
        messageID: UUID? = UUID(),
        replyToMessageID: UUID? = nil,
        timestamp: TimeInterval = Date.now.timeIntervalSince1970,
        counter: Int,
        proxyCounter: Int = 0,
        type: RPGMessageType,
        subType: RPGMessageActionType,
        asMaster: Bool,
        targetId: UUID? = nil,
        audience: GameMessageAudience? = nil,
        purpose: GameMessagePurpose = .event,
        data: NetworkCodableDataType
    ) -> GameNetworkModel {
        let sender: GameSenderModel
        var masterState: GameMasterStateModel?
        if asMaster {
            sender = GameSenderModel(
                id: gameConfig.master.id,
                role: .master,
                name: gameConfig.master.name,
                characterId: nil,
                supporterTier: gameConfig.master.supporterTier
            )
            masterState = GameMasterStateModel(
                state: gameConfig.state,
                adventureId: gameConfig.master.adventureId,
                adventureTitle: gameConfig.master.adventureTitle,
                players: gameRoster.players,
                controls: gameControl.controls,
                features: gameControl.features
            )
        } else {
            let player = gamePlayer
            if player.id == gameConfig.id {
                sender = GameSenderModel(
                    id: player.id,
                    role: player.type,
                    name: player.name,
                    characterId: player.characterId,
                    supporterTier: player.supporterTier
                )
            } else {
                sender = GameSenderModel(id: gameConfig.id, role: .notSet, name: gameName, characterId: nil)
            }
        }
        let resolvedAudience = audience ?? GameNetworkModel.inferredAudience(
            sender: sender,
            type: type,
            subType: subType,
            purpose: purpose,
            data: data,
            targetId: targetId
        )
        return GameNetworkModel(
            messageID: messageID,
            replyToMessageID: replyToMessageID,
            timestamp: timestamp,
            counter: counter,
            proxyCounter: proxyCounter,
            type: type,
            subType: subType,
            masterId: gameConfig.master.id,
            sender: sender,
            masterState: masterState,
            targetId: targetId,
            audience: resolvedAudience,
            purpose: purpose,
            senderPlatform: .current,
            data: data
        )
    }

    var gameType: GameType { gameConfig.type(in: gameRoster) }
    var gameName: String { gameConfig.name(in: gameRoster) }
    var gamePlayer: PlayerGameModel { gameConfig.player(in: gameRoster) }

    func updateLocalSupporterTier(_ supporterTier: SupporterTier) {
        if gameConfig.isMaster,
           gameConfig.master.supporterTier != supporterTier {
            gameConfig.master.supporterTier = supporterTier
        }

        if let localIndex = gameRoster.players.firstIndex(where: { $0.id == gameConfig.id }),
           gameRoster.players[localIndex].supporterTier != supporterTier {
            gameRoster.players[localIndex].supporterTier = supporterTier
        }
    }

    /// `timestamp` is validated only as a freshness/anti-replay sanity bound
    /// (finite, positive, not implausibly far in the future); ordering itself
    /// is decided by `counter`, matching every sibling per-item sequencing
    /// gate (`canApplyAudioList`/`canApplyPhotoList`/`canApplyPdfList`/
    /// `canApplySpaceList`/`canApplySpaceTransform`). See
    /// CODE_AUDIT_Network §5.17.
    func canApplyValueUpdate(
        senderId: UUID,
        characterId: UUID,
        entryId: UUID,
        timestamp: TimeInterval,
        counter: Int
    ) -> Bool {
        guard timestamp.isFinite,
              timestamp > 0,
              timestamp <= Date.now.timeIntervalSince1970
                + GameNetworkModel.maximumFutureEventTimestampSkew else {
            return false
        }
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        let key = ValueUpdateKey(
            senderId: senderId,
            characterId: characterId,
            entryId: entryId
        )
        return counter > (latestValueUpdateCounters[key] ?? 0)
    }

    func peerImportPolicy(senderId: UUID, primaryItemId: UUID) -> PeerImportPolicy {
        PeerImportPolicy(primaryItemId: primaryItemId, ownedItemIds: peerIntroducedItemIds[senderId] ?? [])
    }

    func recordPeerImport(_ policy: PeerImportPolicy, senderId: UUID) {
        peerIntroducedItemIds[senderId] = policy.introducedItemIds
    }

    func recordValueUpdate(
        senderId: UUID,
        characterId: UUID,
        entryId: UUID,
        counter: Int
    ) {
        guard counter > 0 else { return }
        let key = ValueUpdateKey(
            senderId: senderId,
            characterId: characterId,
            entryId: entryId
        )
        if latestValueUpdateCounters[key] == nil {
            latestValueUpdateOrder.append(key)
            // Growable by a peer sending many distinct entryIds — bounded
            // the same way `deliveryMessagesByWireID` is.
            // See CODE_AUDIT_Game §7.5.
            while latestValueUpdateOrder.count > Self.maximumRetainedValueUpdateCounters {
                latestValueUpdateCounters[latestValueUpdateOrder.removeFirst()] = nil
            }
        }
        latestValueUpdateCounters[key] = counter
    }
}

extension GameRootModel {
    /// Notes whether the player behind a shared dice roll sits at the 3D table. The game
    /// master has a seat of their own and is never a guest.
    func noteDiceRollSender(of message: GameNetworkModel) {
        guard !message.sender.isMaster, !message.senderName.isEmpty else { return }
        if message.senderPlatform == .visionOS {
            tableGuestNames.remove(message.senderName)
        } else {
            tableGuestNames.insert(message.senderName)
        }
    }
}
