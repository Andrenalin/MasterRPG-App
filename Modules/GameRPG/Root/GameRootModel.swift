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

    func add(playerId: UUID, playerModel: PlayerGameModel, sharingModel: SharingControlModel) -> Bool {
        // A claimed player model whose id doesn't match the sender is a failed
        // roster lookup (PlayerGameModel.empty carries a random id) — writing it
        // would orphan the roster entry and lose the player's name for good.
        guard playerModel.id == playerId else { return false }

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

@MainActor
public final class GameRoot {
    let adventureRoot: AdventureRootModel
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let mapRoot: MapRootModel
    // var (not let) so tests can inject spy stores; safe under MainActor isolation.
    var networkStore: GameNetworkController
    var networkProxyStore: GameNetworkController
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let ruleRoot: RuleRootModel?
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let weatherRoot: WeatherRootModel

    let gameModel: GameRootModel
    let gameJoinCodeModel = GameJoinCodeModel()
    let statisticsModel: GameStatisticsModel
    let gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    private var networkActionTasks: [UUID: Task<Void, Never>] = [:]
    private var networkActionTail: Task<Void, Never>?
    private var networkActionTailID: UUID?
    private var demoTask: Task<Void, Never>?

    /// Tracks an in-flight `stopGame()` so a `startGame`/`startMaster` call racing an
    /// unstructured `Task { await root.stopGame() }` (fired from `endGame()`) can't have its
    /// freshly-assigned controllers nulled out by the older, still-running teardown. Every
    /// entry point awaits this before proceeding, and `stopGame()` itself coalesces concurrent
    /// callers onto the same in-flight task rather than tearing down twice.
    private var stopGameTask: Task<Void, Never>?

    public init(adventureRoot: AdventureRootModel, audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, ruleRoot: RuleRootModel? = nil, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.ruleRoot = ruleRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.weatherRoot = weatherRoot
        
        self.networkStore = GameNetworkController(name: "Init")
        self.networkProxyStore = GameNetworkController(proxyName: "Proxy")
        
        self.gameModel = GameRootModel()
        let statisticsModel = GameStatisticsModel()
        let gameCenterModel = GameCenterModel()
        let gameCenterController = GameCenterController(model: gameCenterModel)
        self.statisticsModel = statisticsModel
        self.gameCenterModel = gameCenterModel
        self.gameCenterController = gameCenterController
        
        _viewController = ViewController(root: self)
        _logGameController = LogGameController(root: self, gameModel: gameModel)

        statisticsModel.setAchievementReporter { [weak gameCenterController] summary in
            await gameCenterController?.reportAchievements(from: summary)
        }
    }

    private(set) var _viewController: ViewController?
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    private(set) var _logGameController: LogGameController?
    var logGameController: LogGameController {
        _logGameController.unsafelyUnwrapped
    }

    public func updateSupporterTier(_ supporterTier: SupporterTier) {
        gameModel.updateLocalSupporterTier(supporterTier)
    }

    /// This device's own join code — the Master code when hosting, otherwise
    /// this device's Player code (used should it relay for further players).
    /// Always available, mirroring how the Master always sees theirs. Read by
    /// [[GameJoinCodeRevealButton]] and `GameRootViewer`'s empty state.
    func ownJoinCode(isMaster: Bool) -> String? {
        isMaster ? gameJoinCodeModel.masterCode : gameJoinCodeModel.playerCode
    }

    /// Replaces every join code this device has stored in the Keychain with a
    /// freshly generated one. Surfaced from [[SettingsView]]'s Reset section.
    public func resetJoinCodes() {
        gameJoinCodeModel.reset()
    }
    
    lazy var searchController: SearchGlobalController = {
        SearchGlobalController(root: self)
    }()

    /// The single battle-round controller for this game session. Owning it
    /// here (rather than rebuilding its action closures on every render of
    /// the window/sidebar host views) means restarting a battle keeps using
    /// the same `BattleRoundModel` instance, so retained player identity and
    /// initiative carry over as already implemented in `BattleRoundModel`.
    lazy var battleRoundController = BattleRoundController(root: self)

    /// The modules whose `resetPlayers()` shape is a uniform "tell this
    /// module's game model who the current players are" — Map and Dice are
    /// deliberately excluded, since their reset has genuinely different
    /// per-module logic beyond this shared step. See CODE_AUDIT_Game §9.18.
    var fileBackedGameModules: [any GameControllable] {
        [
            audioRoot.gameControllable,
            photoRoot.gameControllable,
            pdfRoot.gameControllable,
            spaceRoot.gameControllable,
            tableRoot.gameControllable,
            weatherRoot.gameControllable
        ]
    }

    #if os(visionOS)
    /// True only while an actual SharePlay `GroupSession` is active — see
    /// `EnvironmentValues.isSpaceSharePlayActive`, which this backs.
    public var isSharePlayActive: Bool { gameModel.isSharePlayActive }
    #endif

    public lazy var networkActions: NetworkActions = NetworkActions { @MainActor [weak self] idType in
        guard let store = self?.gameModel.masterController else { return }
        self?.scheduleNetworkAction {
            await store.show(for: idType)
        }
    } send: { @MainActor [weak self] update in
        let masterStore = self?.gameModel.masterController
        let playerStore = self?.gameModel.playerController
        self?.scheduleNetworkAction {
            if let masterStore {
                await masterStore.send(updated: update)
            } else {
                await playerStore?.send(updated: update)
            }
        }
    } game: { @MainActor [weak self] message, actionType, playerId in
        let masterStore = self?.gameModel.masterController
        let playerStore = self?.gameModel.playerController
        self?.scheduleNetworkAction {
            if let masterStore {
                await masterStore.game(message: message, actionType: actionType, playerId: playerId)
            } else {
                await playerStore?.game(message: message, actionType: actionType)
            }
        }
    }

    public lazy var sharingControlActions: SharingControlActions = SharingControlActions(id: .object(ObjectIdentifier(self))) { [weak self] in
        self?.gameModel.gameControl.controls ?? []
    } update: { [weak self] newControls in
        if self?.gameModel.gameControl.controls != newControls {
            self?.gameModel.gameControl.controls = newControls
        }
        self?.scheduleNetworkAction {
            await self?.gameModel.masterController?.resetPlayers()
        }
    }

    public lazy var sharingFeatureActions: SharingFeatureActions = SharingFeatureActions(id: .object(ObjectIdentifier(self))) { [weak self] in
        self?.gameModel.gameControl.features ?? GameFeatureModel()
    }
    
    var characterName: String {
        if let selectedCharacter = gameModel.selectedCharacter {
            return characterRoot.linkControllable.name(for: selectedCharacter)
        } else {
            return String(localized: "Unknown", bundle: .module)
        }
    }

    var gameMasterName: String {
        String(localized: "GameMaster", bundle: .module).localizedString
    }

    private func scheduleNetworkAction(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let id = UUID()
        let previous = networkActionTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else {
                self?.completeNetworkAction(id: id)
                return
            }
            await operation()
            self?.completeNetworkAction(id: id)
        }
        networkActionTasks[id] = task
        networkActionTail = task
        networkActionTailID = id
    }

    private func completeNetworkAction(id: UUID) {
        networkActionTasks.removeValue(forKey: id)
        if networkActionTailID == id {
            networkActionTail = nil
            networkActionTailID = nil
        }
    }

    private func cancelOwnedTasks() {
        networkActionTasks.values.forEach { $0.cancel() }
        networkActionTasks.removeAll()
        networkActionTail = nil
        networkActionTailID = nil
        demoTask?.cancel()
        demoTask = nil
    }
}

// MARK: - Master / Player selection views and handling

extension GameRoot {
    func resetSelectedAdventure(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedAdventure != nil {
                gameModel.selectedAdventure = nil
            }
            return
        }
        gameModel.selectedAdventure <=> uuid
    }

    func resetSelectedCharacter(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedCharacter != nil {
                gameModel.selectedCharacter = nil
            }
            return
        }
        gameModel.selectedCharacter <=> uuid
    }

    func resetSelectedGameMaster(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            if gameModel.selectedGameMaster != nil {
                gameModel.selectedGameMaster = nil
            }
            return
        }
        gameModel.selectedGameMaster <=> uuid
    }
}

// MARK: - Master Control Game

extension GameRoot {
    func startMaster(supporterTier: SupporterTier = .none) async {
        await awaitInFlightStop()
        guard gameModel.gameConfig.state == .stopped else {
            await stopGame()
            return
        }
        guard let id = gameModel.selectedAdventure else {
            return
        }

        let adventureTitle = adventureRoot.networkTitle(for: id)
        let masterGameModel = MasterGameModel(
            id: UUID(),
            type: .master,
            name: gameMasterName,
            adventureId: id,
            adventureTitle: adventureTitle,
            supporterTier: supporterTier
        )
        var newConfig = gameModel.gameConfig
        newConfig.id = masterGameModel.id
        newConfig.master = masterGameModel
        gameModel.gameConfig = newConfig
        gameModel.startGameTime = Date.now
        #if os(visionOS)
        gameModel.shareState.isMaster = true
        #endif

        // Bonjour advertises the adventure title (falling back to "GameMaster"
        // when it's empty) plus the supporter tier, so browsing players see
        // what adventure they're joining rather than a generic device label.
        let advertisedName = adventureTitle.isEmpty ? gameMasterName : adventureTitle
        networkStore.resetName(name: advertisedName, supporterTier: supporterTier)
        networkProxyStore.resetName(name: advertisedName, supporterTier: supporterTier)
        networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)

        await adventureRoot.adventureGameControllable.startGame(with: id)
        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
        gameModel.masterController = MasterController(root: self, asProxy: false)

        gameModel.gameConfig.state = .started
        adventureRoot.startGame()

        await beginStatisticsSession(for: .master, at: gameModel.startGameTime)

        await gameModel.masterController?.start()
        await diceRoot.diceGameControllable.setFocusDice(on: adventureRoot.adventureGameControllable.focusDice(for: id))
        
#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = true
#endif
    }
}

// MARK: - Player Control Game

extension GameRoot {
    private func name(for type: GameType) -> String {
        switch type {
        case .observer:
            return String(localized: "Observer", bundle: .module)
        case .proxy:
            return String(localized: "Proxy", bundle: .module)
        default:
            return characterName
        }
    }

    func startGame(
        to model: BrowserGameModel?,
        mode: GameType,
        supporterTier: SupporterTier = .none,
        joinCode: String = ""
    ) async {
        await awaitInFlightStop()
        // Observer is intentionally Bonjour/LAN-only. Enforce this at the domain
        // boundary as well as in the setup UI so programmatic callers cannot join
        // SharePlay by passing a nil target.
        guard mode != .observer || model != nil else { return }
        if (mode == .proxy || mode == .observer || mode == .demo) {
            gameModel.selectedCharacter = nil
        }
        let playerGameModel = PlayerGameModel(
            id: UUID(),
            type: mode,
            name: name(for: mode),
            characterId: gameModel.selectedCharacter,
            supporterTier: supporterTier
        )
        gameModel.gameRoster = GameRosterModel(players: [playerGameModel])
        gameModel.gameControl = .empty
        var newConfig = gameModel.gameConfig
        newConfig.id = playerGameModel.id
        newConfig.state = .prepare
        gameModel.gameConfig = newConfig
        networkStore.resetName(name: name(for: mode), supporterTier: supporterTier)
        if mode == .player {
            networkProxyStore.resetName(name: characterName, supporterTier: supporterTier)
            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
        }

        await adventureRoot.adventureGameControllable.resetGame()
        #if os(visionOS)
        gameModel.shareState.isMaster = false
        #endif
        let player = PlayerController(root: self, asGameMaster: mode == .demo)
        gameModel.playerController = player

        if mode == .demo {
            await joinGame(for: mode, supporterTier: supporterTier)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else if await player.start(to: model, joinCode: joinCode) {
            await joinGame(for: mode, supporterTier: supporterTier)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else {
            await stopGame()
        }
    }

    func joinGame(
        for type: GameType,
        supporterTier: SupporterTier = .none
    ) async {
        gameModel.startGameTime = Date.now
        gameModel.playerGameStarted = true
        var newConfig = gameModel.gameConfig
        newConfig.state = .started
        gameModel.gameConfig = newConfig
        // Update the local player by id, not by index: a master broadcast
        // processed during connect can already have replaced the roster, and
        // index 0 may then be another player's entry.
        if let index = gameModel.gameRoster.players.firstIndex(where: { $0.id == gameModel.gameConfig.id }) {
            gameModel.gameRoster.players[index].type = type
            gameModel.gameRoster.players[index].name = name(for: type)
            gameModel.gameRoster.players[index].characterId = gameModel.selectedCharacter
            gameModel.gameRoster.players[index].supporterTier = supporterTier
        } else {
            gameModel.gameRoster.players.append(
                PlayerGameModel(
                    id: gameModel.gameConfig.id,
                    type: type,
                    name: name(for: type),
                    characterId: gameModel.selectedCharacter,
                    supporterTier: supporterTier
                )
            )
        }
        adventureRoot.startGame()
        if type != .observer {
            await characterRoot.valueGameControllable.startGame(for: gameModel.selectedCharacter)
            await diceRoot.diceGameControllable.setFocusDice(on: characterRoot.valueGameControllable.focusDice(for: gameModel.selectedCharacter ?? UUID()))
        }
        await beginStatisticsSession(for: type, at: gameModel.startGameTime)
    }

    // both
    func stopGame() async {
        // Coalesce concurrent callers onto the single in-flight teardown instead of running
        // it twice (or racing a fresh `startGame` — see `awaitInFlightStop()`).
        if let stopGameTask {
            await stopGameTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performStopGame()
        }
        stopGameTask = task
        await task.value
        stopGameTask = nil
    }

    private func awaitInFlightStop() async {
        await stopGameTask?.value
    }

    private func performStopGame() async {
        cancelOwnedTasks()
        mapRoot.mapGameControllable.resetBattleRound()
        await statisticsModel.checkpoint(participants: currentStatisticParticipants())
        await statisticsModel.finishSession()
        gameModel.playerGameStarted = false
        gameModel.gameConfig.state = .stopped
        gameModel.gameConfig = .empty
        await gameModel.masterController?.stop()
        gameModel.masterController = nil
        await gameModel.playerController?.stop()
        gameModel.playerController = nil
        await adventureRoot.adventureGameControllable.resetGame()
        #if !os(tvOS)
        gameModel.gameTableModel = nil
        #endif
        #if os(visionOS)
        gameModel.shareState = GameShareStateModel()
        #endif

#if !os(macOS)
        UIApplication.shared.isIdleTimerDisabled = false
#endif
    }

    func saveGame() -> ItemModuleIds {
        adventureRoot.adventureGameControllable.saveGame()
    }
}

// MARK: - Demo

extension GameRoot {
    /// Pacing between each photo reveal, and between map-state update steps, in the
    /// auto-playing demo sequence. See CODE_AUDIT §9.14.
    private static let demoRevealPace: Duration = .seconds(3)
    /// Pacing before revealing each weather or map in the demo sequence — longer than
    /// `demoRevealPace` since these are bigger visual changes to let settle.
    /// See CODE_AUDIT §9.14.
    private static let demoBigRevealPace: Duration = .seconds(5)

    func startDemo(supporterTier: SupporterTier = .none) async {
        await startGame(to: nil, mode: .demo, supporterTier: supporterTier)
        demoTask?.cancel()

        if let playerController = gameModel.playerController {
            demoTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled && gameModel.gameConfig.state != .stopped {
                    let photos = photoRoot.itemControllable.itemDataModel.items
                    for photo in photos {
                        do {
                            try await Task.sleep(for: Self.demoRevealPace)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        let data = await photoRoot.gameControllable.share(id: photo)
                        let gameNetworkModel = gameModel.outgoingMessage(counter: 1, type: .reveal, subType: .show, asMaster: true, data: data)
                        await playerController.receivedProcess(gameNetworkModel)
                    }
                    
                    let weathers = weatherRoot.itemControllable.itemDataModel.items
                    for weather in weathers {
                        do {
                            try await Task.sleep(for: Self.demoBigRevealPace)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        let data = await weatherRoot.gameControllable.share(id: weather)
                        let gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .reveal, subType: .show, asMaster: true, data: data)
                        await playerController.receivedProcess(gameNetworkModel)
                    }
                    
                    let maps = mapRoot.itemControllable.itemDataModel.items
                    for map in maps {
                        do {
                            try await Task.sleep(for: Self.demoBigRevealPace)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        let data = await mapRoot.mapGameControllable.shareMap(id: map)
                        let gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .reveal, subType: .show, asMaster: true, data: data)
                        await playerController.receivedProcess(gameNetworkModel)
                        
                        var showMap = true
                        
                        while showMap {
                            var data = mapRoot.mapGameControllable.demoNextMap(itemId: map, restart: false)
                            if data == nil {
                                data = mapRoot.mapGameControllable.demoNextMap(itemId: map, restart: true)
                                showMap = false
                            }
                            guard let data else { break }
                            do {
                                try await Task.sleep(for: Self.demoRevealPace)
                            } catch {
                                return
                            }
                            guard !Task.isCancelled else { return }

                            let gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .update, subType: .mapState, asMaster: true, data: data)
                            await playerController.receivedProcess(gameNetworkModel)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Search Helpers

extension GameRoot {
    func rootController(for module: NetworkModules) -> ItemRootController {
        switch module {
        case .adventure:
            return adventureRoot.rootController
        case .audio:
            return audioRoot.rootController
        case .value:
            return characterRoot.rootController
        case .dice:
            return diceRoot.rootController
        case .map:
            return mapRoot.rootController
        case .pdf:
            return pdfRoot.rootController
        case .photo:
            return photoRoot.rootController
        case .rule:
            // `searchAllItems()` only ever produces `.rule` results when `ruleRoot` exists, so
            // this should never be reached with a nil `ruleRoot`. Assert loudly in debug builds
            // rather than silently mislabeling Adventure content as a Rule search result.
            guard let ruleRoot else {
                assertionFailure("rootController(for: .rule) called with a nil ruleRoot")
                return adventureRoot.rootController
            }
            return ruleRoot.rootController
        case .space:
            return spaceRoot.rootController
        case .table:
            return tableRoot.rootController
        case .weather:
            return weatherRoot.rootController
        default:
            return adventureRoot.rootController
        }
    }
}
