// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import GroupActivities
import os.log
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
    /// The quick dice overlay's slots. Public so the app can hand them to every scene, including
    /// the character's own window on macOS and visionOS.
    public let quickDiceSlots = QuickDiceSlotsModel()
    let gameJoinCodeModel: GameJoinCodeModel
    let statisticsModel: GameStatisticsModel
    let gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    var networkActionTasks: [UUID: Task<Void, Never>] = [:]
    var networkActionTail: Task<Void, Never>?
    var networkActionTailId: UUID?
    var demoTask: Task<Void, Never>?

    /// Tracks an in-flight `stopGame()` so a `startGame`/`startMaster` call racing an
    /// unstructured `Task { await root.stopGame() }` (fired from `endGame()`) can't have its
    /// freshly-assigned controllers nulled out by the older, still-running teardown. Every
    /// entry point awaits this before proceeding, and `stopGame()` itself coalesces concurrent
    /// callers onto the same in-flight task rather than tearing down twice.
    var stopGameTask: Task<Void, Never>?
    /// Whether a quit is tearing the game down. The game's state is still `.started` until the
    /// teardown reaches its end, so a view that mounts meanwhile must not read it as running.
    var isStopping: Bool { stopGameTask != nil }
    /// Which `stopGame` call created `stopGameTask`: only that teardown may clear it.
    var stopGameTaskToken: UUID?
    /// A `startGame` is running: a second call (double tap, intent and UI together) would reset
    /// the roster and the player controller under the first.
    var isStartingGame = false

    /// Set synchronously at the top of `startMaster` and cleared when it returns. The game is
    /// only `.started` after the adventure's game start has been awaited, so a second call in
    /// that window used to pass the `.stopped` guard and build a second master id and a second
    /// controller pair. See CODE_AUDIT_21 §3.2.
    var isStartingMaster = false

    /// Bumped by every `stopGame`. A start that was running during a stop compares it after its
    /// suspensions and gives up, instead of building controllers and a `.started` game on top
    /// of the teardown. See CODE_AUDIT_23 §3.1.
    var stopGeneration = 0

    public init(adventureRoot: AdventureRootModel, audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, ruleRoot: RuleRootModel? = nil, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel, gameJoinCodeModel: GameJoinCodeModel = GameJoinCodeModel()) {
        self.gameJoinCodeModel = gameJoinCodeModel
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
        
        statisticsModel.setAchievementReporter { [weak gameCenterController] summary in
            await gameCenterController?.reportAchievements(from: summary)
        }
        restoreSelectedCharacter()
        adventureRoot.selectAdventureForGame = { [weak self] adventureId in
            self?.selectAdventureForGame(adventureId) ?? false
        }
    }

    /// Created on first use: it needs `self`, which the force-unwrapped optional set at the end
    /// of `init` used to work around. See CODE_AUDIT_29 §9.8.
    @ObservationIgnored private(set) lazy var logGameController = LogGameController(root: self, gameModel: gameModel)

    public func updateSupporterTier(_ supporterTier: SupporterTier) {
        gameModel.updateLocalSupporterTier(supporterTier)
    }

    /// This device's own join code — the Master code when hosting, otherwise
    /// this device's Player code (used should it relay for further players).
    /// Always available, mirroring how the Master always sees theirs. Read by
    /// [[GameJoinCodeRevealButton]] and `GameRootViewer`'s empty state.
    ///
    /// While a listener is running it keeps the code it was started with even if the stored one
    /// changes afterwards (Settings reset), so that running code is shown instead of the stored
    /// one — otherwise players would be told a code the listener does not accept.
    /// See CODE_AUDIT_Join §5.8.
    ///
    /// Observers and proxies never host (no listener, no Bonjour advertising — only the Game
    /// Master and a player relay do), so they have no code to share and get `nil`.
    func ownJoinCode(isMaster: Bool) -> String? {
        if !isMaster, !offersJoinCode(for: gameModel.gameType) { return nil }
        let store = isMaster ? networkStore : networkProxyStore
        if let hosting = store.model.masterStore?.networkModel, hosting.isStreaming, !hosting.passcode.isEmpty {
            return hosting.passcode
        }
        return isMaster ? gameJoinCodeModel.masterCode : gameJoinCodeModel.playerCode
    }

    /// Whether a device in `type` hosts a listener other devices can join, and so has a join
    /// code to show. Observers and proxies only connect out. Must match the roles for which
    /// `PlayerController.start` starts a proxy server.
    func offersJoinCode(for type: GameType) -> Bool {
        switch type {
        case .observer, .proxy: false
        case .notSet, .master, .player, .demo: true
        }
    }

    /// The local-network connection was lost and this device is waiting for the master to dial back
    /// in. Read by every connection-status indicator so none can omit it.
    /// See CODE_AUDIT_Join §8.3.
    var isLocalNetworkReconnecting: Bool {
        networkStore.model.playerStore?.networkModel.connectionState == .lost
    }

    /// What the Game Master's own status icon should show when hosting is degraded; `nil` when
    /// hosting is healthy (or this device is not the master). See CODE_AUDIT_Join §5.3.
    func hostingStatus(isMaster: Bool) -> GameConnectionStatusPresentation? {
        guard isMaster else { return nil }
        switch networkStore.model.masterStore?.networkModel.listenerStatus {
        case .restarting, .starting, .waiting: return .localNetworkReconnecting
        case .failed: return .localNetworkLost
        default: return nil
        }
    }

    /// Called when the app becomes active while a game is showing: resolves join codes that could
    /// not be read earlier and restarts hosting services that stopped in the background.
    /// See CODE_AUDIT_Join §5.3.
    func applicationBecameActive() {
        let isHosting = networkStore.model.masterStore?.networkModel.isStreaming == true
        gameJoinCodeModel.refreshFromStorage(keepingMasterCode: isHosting)
        networkStore.resumeAfterActivation()
        networkProxyStore.resumeAfterActivation()
    }

    /// Replaces every join code this device has stored in the Keychain with a
    /// freshly generated one. Surfaced from [[SettingsView]]'s Reset section.
    public func resetJoinCodes() {
        gameJoinCodeModel.reset()
    }
    
    lazy var searchController: SearchGlobalController = {
        SearchGlobalController(root: self)
    }()

    /// Fills the cross-module search with `term`; the search list runs it as soon as it is on
    /// screen. Used by the app-level search intent (CODE_AUDIT_AppIntents §4.1). A level search
    /// ("level 4 adventures") becomes the level token.
    public func showSearchResults(for term: String) {
        searchController.model.show(term: term)
    }

    /// Fills the cross-module search with a level search. Used by the Find by Level intent.
    public func showLevelSearch(_ query: LevelSearchQuery) {
        searchController.model.show(levelQuery: query)
    }

    /// The single battle-round controller for this game session. Owning it
    /// here (rather than rebuilding its action closures on every render of
    /// the window/sidebar host views) means restarting a battle keeps using
    /// the same `BattleRoundModel` instance, so retained player identity and
    /// initiative carry over as already implemented in `BattleRoundModel`.
    lazy var battleRoundController = BattleRoundController(root: self)

    /// The battle round messages last sent, so `battleRoundController` skips
    /// a broadcast that would repeat them.
    let battleRoundBroadcastLog = BattleRoundBroadcastLog()

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

    /// Whether this device joined a running game as a player or observer; see
    /// `EnvironmentValues.isGamePlayer`.
    public var isGamePlayer: Bool {
        gameModel.playerController != nil && !gameModel.gameConfig.isMaster
    }

    public lazy var networkActions: NetworkActions = NetworkActions { @MainActor [weak self] idType in
        guard let store = self?.gameModel.masterController else { return }
        self?.scheduleNetworkAction {
            await store.show(for: idType)
        }
    } send: { @MainActor [weak self] update in
        // A full update carries the map's pins: the battle round's dedupe must not skip a
        // revert after it. See CODE_AUDIT_29 §5.6.
        self?.battleRoundBroadcastLog.noteSend(actionType: .generic, type: update.type)
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
        self?.battleRoundBroadcastLog.noteSend(actionType: actionType, type: message.type)
        let masterStore = self?.gameModel.masterController
        let playerStore = self?.gameModel.playerController
        self?.scheduleNetworkAction {
            if let masterStore {
                await masterStore.game(message: message, actionType: actionType, playerId: playerId)
            } else {
                await playerStore?.game(message: message, actionType: actionType)
            }
        }
    } clearMap: { @MainActor [weak self] shareWithPlayers in
        self?.scheduleMapClear(shareWithPlayers: shareWithPlayers)
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

    /// Pauses or resumes the updates the game master sends one device. Takes the same path as
    /// the sharing controls: `resetPlayers()` then applies the change.
    func setSharing(_ show: Bool, for player: PlayerGameModel) {
        var controls = gameModel.gameControl.controls
        if let index = controls.firstIndex(where: { $0.id == player.id }) {
            guard controls[index].show != show else { return }
            controls[index].show = show
        } else {
            controls.append(SharingControlModel(id: player.id, name: player.name, show: show))
        }
        sharingControlActions.update?(controls)
    }

    /// Whether this device's audio transport may go through the game: a player's commands are
    /// dropped by the game master while audio sharing is off. See CODE_AUDIT_Audio2 §5.14.
    public var isAudioSharingEnabled: Bool { gameModel.gameControl.features.audioSharing }

    public lazy var sharingFeatureActions: SharingFeatureActions = SharingFeatureActions(id: .object(ObjectIdentifier(self))) { [weak self] in
        self?.gameModel.gameControl.features ?? GameFeatureModel()
    }
    
    /// "Generate Map" in the photo list: a map made from the photo in game memory only, shown to
    /// the players. Only the game master of a running game gets it, and only the map: Characters
    /// are made in the editor.
    public var generateFromPhotoAction: GenerateFromPhotoAction {
        GenerateFromPhotoAction(
            id: .object(ObjectIdentifier(self)),
            kinds: gameModel.gameConfig.isMaster && gameModel.gameConfig.state != .stopped ? [.map] : []
        ) { [weak self] _, photoId in
            guard let store = self?.gameModel.masterController else { return }
            self?.scheduleNetworkAction { [weak self] in
                guard let reference = await self?.mapRoot.mapGameControllable.createTemporaryMap(photoId: photoId) else { return }
                await store.show(for: reference)
            }
        }
    }

    var characterName: String {
        if let selectedCharacter = gameModel.selectedCharacter {
            return characterRoot.linkControllable.name(for: selectedCharacter)
        } else {
            return String(localized: "Unknown", bundle: .module)
        }
    }

    var gameMasterName: String {
        String(localized: "GameMaster", bundle: .module)
    }

    /// Sends the game master's change of a photo shown over the map, in order with the other
    /// network actions.
    func scheduleMapPhotoBroadcast(_ presentation: MapPhotoPresentation) {
        guard let store = gameModel.masterController else { return }
        scheduleNetworkAction {
            await store.broadcastMapPhoto(presentation)
        }
    }

    /// Takes the shown map off the screens, in order with the game master's other changes.
    func scheduleMapClear(shareWithPlayers: Bool) {
        guard let store = gameModel.masterController else { return }
        scheduleNetworkAction {
            await store.clearShownMap(shareWithPlayers: shareWithPlayers)
        }
    }

    /// Clears the weather from every 3D table, in order with the game master's other changes.
    func scheduleTableWeatherClear() {
        guard let store = gameModel.masterController else { return }
        scheduleNetworkAction {
            await store.clearTableWeather()
        }
    }

    /// Runs `operation` after the network actions scheduled before it, and cancels it with the game.
    func scheduleNetworkAction(_ operation: @escaping @MainActor @Sendable () async -> Void) {
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
        networkActionTailId = id
    }

    private func completeNetworkAction(id: UUID) {
        networkActionTasks.removeValue(forKey: id)
        if networkActionTailId == id {
            networkActionTail = nil
            networkActionTailId = nil
        }
    }

    func cancelOwnedTasks() {
        networkActionTasks.values.forEach { $0.cancel() }
        networkActionTasks.removeAll()
        networkActionTail = nil
        networkActionTailId = nil
        demoTask?.cancel()
        demoTask = nil
        mapRoot.rootModel.cancelMapContentSends()
    }
}

// MARK: - Master / Player selection views and handling

extension GameRoot {
    /// Chooses the adventure the Game screen starts with, as picking it there does: the Siri and
    /// Shortcuts "Start Adventure Game" intent only prepares the game, the game master starts it.
    /// The choice is also stored where the setup screen restores it from, because a setup screen
    /// that is not on screen yet reads the stored value when it appears. Nothing is changed while
    /// a game is starting or running. Returns whether the adventure was chosen.
    /// See CODE_AUDIT §5.1.
    @discardableResult
    func selectAdventureForGame(_ adventureId: UUID) -> Bool {
        guard gameModel.gameConfig.state == .stopped, !isStartingMaster, !isStartingGame else { return false }
        UserDefaults.standard.set(adventureId.uuidString, forKey: GameStorageKeys.lastAdventureUUID)
        gameModel.selectedAdventure <=> adventureId
        return true
    }

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

    /// Loads the character saved on the player setup screen when none is selected yet. Only that
    /// screen's `.task` used to load it, so Join Game by Siri failed in a run where the screen had
    /// not appeared. See CODE_AUDIT_Since_3.0.1 §5.7.
    func restoreSelectedCharacter(defaults: UserDefaults = .standard) {
        guard gameModel.selectedCharacter == nil else { return }
        resetSelectedCharacter(uuidString: defaults.string(forKey: GameStorageKeys.lastPlayerUUID) ?? "")
    }
}
