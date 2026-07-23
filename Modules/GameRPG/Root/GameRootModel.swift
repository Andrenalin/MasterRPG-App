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
    var playerScreens: [UUID: Data] = [:]
    var attachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
    var metaDataAttachments: [NetworkModules: UUID] = [:]
    private var latestValueUpdateTimestamps: [ValueUpdateKey: TimeInterval] = [:]

    var masterController: MasterController?
    var playerController: PlayerController?

    #if !os(tvOS)
    var gameTableModel: GameTableModel?
    #endif

    #if os(visionOS)
    var shareState = GameShareStateModel()
    #endif

    func add(playerId: UUID, playerModel: PlayerGameModel, sharingModel: SharingControlModel) -> Bool {
        // A claimed player model whose id doesn't match the sender is a failed
        // roster lookup (PlayerGameModel.empty carries a random id) — writing it
        // would orphan the roster entry and lose the player's name for good.
        guard playerModel.id == playerId else { return false }

        let isNewPlayer: Bool
        if let index = gameRoster.players.firstIndex(where: { $0.id == playerId }) {
            gameRoster.players[index] = playerModel
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
        latestValueUpdateTimestamps = [:]
    }

    func reset(master: MasterGameModel) {
        gameConfig.master = master
    }

    /// Applies a master broadcast in one atomic step so concurrent readers
    /// (message building, sendCharacter) never observe a half-updated state.
    func applyMasterBroadcast(masterId: UUID, masterName: String, state: GameMasterStateModel) {
        gameConfig.master = MasterGameModel(id: masterId, type: .master, name: masterName, adventureId: state.adventureId, adventureTitle: state.adventureTitle)
        gameControl.controls = state.controls
        gameControl.features = state.features

        var updatedPlayers = state.players
        if !updatedPlayers.contains(where: { $0.id == gameConfig.id }) {
            // Keep the local player in the roster, but never append the `.empty`
            // fallback — its random id would poison every later lookup.
            let localPlayer = gamePlayer
            if localPlayer.id == gameConfig.id {
                updatedPlayers.append(localPlayer)
            }
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
            sender = GameSenderModel(id: gameConfig.master.id, role: .master, name: gameConfig.master.name, characterId: nil)
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
                sender = GameSenderModel(id: player.id, role: player.type, name: player.name, characterId: player.characterId)
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

    func canApplyValueUpdate(
        senderId: UUID,
        characterId: UUID,
        entryId: UUID,
        timestamp: TimeInterval
    ) -> Bool {
        guard timestamp.isFinite,
              timestamp > 0,
              timestamp <= Date.now.timeIntervalSince1970
                + GameNetworkModel.maximumFutureEventTimestampSkew else {
            return false
        }
        let key = ValueUpdateKey(
            senderId: senderId,
            characterId: characterId,
            entryId: entryId
        )
        return timestamp > (latestValueUpdateTimestamps[key] ?? 0)
    }

    func recordValueUpdate(
        senderId: UUID,
        characterId: UUID,
        entryId: UUID,
        timestamp: TimeInterval
    ) {
        latestValueUpdateTimestamps[
            ValueUpdateKey(
                senderId: senderId,
                characterId: characterId,
                entryId: entryId
            )
        ] = timestamp
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
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let weatherRoot: WeatherRootModel

    let gameModel: GameRootModel
    let statisticsModel: GameStatisticsModel
    let gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    private var networkActionTasks: [UUID: Task<Void, Never>] = [:]
    private var networkActionTail: Task<Void, Never>?
    private var networkActionTailID: UUID?
    private var demoTask: Task<Void, Never>?

    public init(adventureRoot: AdventureRootModel, audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        self.adventureRoot = adventureRoot
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
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
    
    lazy var searchController: SearchGlobalController = {
        SearchGlobalController(root: self)
    }()

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

    public lazy var sharingControlActions: SharingControlActions = SharingControlActions { [weak self] in
        self?.gameModel.gameControl.controls ?? []
    } update: { [weak self] newControls in
        if self?.gameModel.gameControl.controls != newControls {
            self?.gameModel.gameControl.controls = newControls
        }
        self?.scheduleNetworkAction {
            await self?.gameModel.masterController?.resetPlayers()
        }
    }

    public lazy var sharingFeatureActions: SharingFeatureActions = SharingFeatureActions { [weak self] in
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
    func startMaster() async {
        guard gameModel.gameConfig.state == .stopped else {
            await stopGame()
            return
        }
        guard let id = gameModel.selectedAdventure else {
            return
        }
        
        let masterGameModel = MasterGameModel(id: UUID(), type: .master, name: gameMasterName, adventureId: id, adventureTitle: adventureRoot.networkTitle(for: id))
        var newConfig = gameModel.gameConfig
        newConfig.id = masterGameModel.id
        newConfig.master = masterGameModel
        gameModel.gameConfig = newConfig
        gameModel.startGameTime = Date.now
        #if os(visionOS)
        gameModel.shareState.isMaster = true
        #endif
        
        networkStore.resetName(name: gameMasterName)
        networkProxyStore.resetName(name: gameMasterName)
        networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)

        await adventureRoot.adventureGameControllable.startGame(with: id)
        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
        gameModel.masterController = MasterController(root: self, asProxy: false)

        gameModel.gameConfig.state = .started
        adventureRoot.startGame()

        await beginStatisticsSession(for: .master, at: gameModel.startGameTime)

        await gameModel.masterController?.start()
        await diceRoot.diceGameControllable.setFocusDice(on: adventureRoot.adventureGameControllable.focusDice(for: gameModel.selectedAdventure!))
        
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

    func startGame(to model: BrowserGameModel?, mode: GameType) async {
        // Observer is intentionally Bonjour/LAN-only. Enforce this at the domain
        // boundary as well as in the setup UI so programmatic callers cannot join
        // SharePlay by passing a nil target.
        guard mode != .observer || model != nil else { return }
        if (mode == .proxy || mode == .observer || mode == .demo) {
            gameModel.selectedCharacter = nil
        }
        let playerGameModel = PlayerGameModel(id: UUID(), type: mode, name: name(for: mode), characterId: gameModel.selectedCharacter)
        gameModel.gameRoster = GameRosterModel(players: [playerGameModel])
        gameModel.gameControl = .empty
        var newConfig = gameModel.gameConfig
        newConfig.id = playerGameModel.id
        newConfig.state = .prepare
        gameModel.gameConfig = newConfig
        networkStore.resetName(name: name(for: mode))
        if mode == .player {
            networkProxyStore.resetName(name: characterName)
            networkStore.sharePlayStore.setup(audioCoordinator: audioRoot.audioCoordinatorPlayback)
        }

        await adventureRoot.adventureGameControllable.resetGame()
        #if os(visionOS)
        gameModel.shareState.isMaster = false
        #endif
        let player = PlayerController(root: self, asGameMaster: mode == .demo)
        gameModel.playerController = player

        if mode == .demo {
            await joinGame(for: mode)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else if await player.start(to: model) {
            await joinGame(for: mode)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else {
            await stopGame()
        }
    }

    func joinGame(for type: GameType) async {
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
        } else {
            gameModel.gameRoster.players.append(PlayerGameModel(id: gameModel.gameConfig.id, type: type, name: name(for: type), characterId: gameModel.selectedCharacter))
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
    func startDemo() async {
        await startGame(to: nil, mode: .demo)
        demoTask?.cancel()

        if let playerController = gameModel.playerController {
            demoTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled && gameModel.gameConfig.state != .stopped {
                    let photos = photoRoot.itemControllable.itemDataModel.items
                    for photo in photos {
                        do {
                            try await Task.sleep(for: .seconds(3))
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
                            try await Task.sleep(for: .seconds(5))
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
                            try await Task.sleep(for: .seconds(5))
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
                                try await Task.sleep(for: .seconds(3))
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
            adventureRoot.rootController
        case .audio:
            audioRoot.rootController
        case .value:
            characterRoot.rootController
        case .dice:
            diceRoot.rootController
        case .map:
            mapRoot.rootController
        case .pdf:
            pdfRoot.rootController
        case .photo:
            photoRoot.rootController
        case .space:
            spaceRoot.rootController
        case .table:
            tableRoot.rootController
        case .weather:
            weatherRoot.rootController
        default:
            adventureRoot.rootController
        }
    }
}

// MARK: - Widget

extension GameRoot {
    func widgetGameRunningChanged() {
        if gameModel.gameConfig.state == .started {
            let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
            defaults?.set(true, forKey: UserDefaults.DiceKeys.isGameActive)
            defaults?.set(gameModel.gameConfig.master.adventureTitle, forKey: UserDefaults.DiceKeys.currentGameName)
            diceRoot.diceGameControllable.clearAllFavoriteDice()
        } else {
            let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
            defaults?.set(false, forKey: UserDefaults.DiceKeys.isGameActive)
            defaults?.set("", forKey: UserDefaults.DiceKeys.currentGameName)
            diceRoot.diceGameControllable.clearAllFavoriteDice()
        }
    }
}
