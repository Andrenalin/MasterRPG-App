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
    /// Which `stopGame` call created `stopGameTask`: only that teardown may clear it.
    private var stopGameTaskToken: UUID?
    /// A `startGame` is running: a second call (double tap, intent and UI together) would reset
    /// the roster and the player controller under the first.
    private var isStartingGame = false

    /// Set synchronously at the top of `startMaster` and cleared when it returns. The game is
    /// only `.started` after the adventure's game start has been awaited, so a second call in
    /// that window used to pass the `.stopped` guard and build a second master id and a second
    /// controller pair. See CODE_AUDIT_21 §3.2.
    private var isStartingMaster = false

    /// Bumped by every `stopGame`. A start that was running during a stop compares it after its
    /// suspensions and gives up, instead of building controllers and a `.started` game on top
    /// of the teardown. See CODE_AUDIT_23 §3.1.
    private var stopGeneration = 0

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
        
        _logGameController = LogGameController(root: self, gameModel: gameModel)

        statisticsModel.setAchievementReporter { [weak gameCenterController] summary in
            await gameCenterController?.reportAchievements(from: summary)
        }
        restoreSelectedCharacter()
    }

    // Force-unwrapped with `!` rather than `.unsafelyUnwrapped`: both backing
    // properties are unconditionally assigned at the end of `init`, so this
    // should never trap in practice, but `!` still traps with a diagnosable
    // crash log if a future refactor (deferred/lazy construction, a new
    // failable init path) ever leaves one `nil` — `.unsafelyUnwrapped` would
    // instead be undefined behavior in a Release build. See CODE_AUDIT §5.2.
    private(set) var _logGameController: LogGameController?
    var logGameController: LogGameController {
        _logGameController!
    }

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
    func ownJoinCode(isMaster: Bool) -> String? {
        let store = isMaster ? networkStore : networkProxyStore
        if let hosting = store.model.masterStore?.networkModel, hosting.isStreaming, !hosting.passcode.isEmpty {
            return hosting.passcode
        }
        return isMaster ? gameJoinCodeModel.masterCode : gameJoinCodeModel.playerCode
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
    /// screen. Used by the app-level search intent (CODE_AUDIT_AppIntents §4.1).
    public func showSearchResults(for term: String) {
        searchController.model.searchText = term
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
    /// the players. Only the game master of a running game gets it.
    public var generateMapAction: GenerateMapAction {
        GenerateMapAction(
            id: .object(ObjectIdentifier(self)),
            isEnabled: gameModel.gameConfig.isMaster && gameModel.gameConfig.state != .stopped
        ) { [weak self] photoId in
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
        String(localized: "GameMaster", bundle: .module).localizedString
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

    /// Loads the character saved on the player setup screen when none is selected yet. Only that
    /// screen's `.task` used to load it, so Join Game by Siri failed in a run where the screen had
    /// not appeared. See CODE_AUDIT_Since_3.0.1 §5.7.
    func restoreSelectedCharacter(defaults: UserDefaults = .standard) {
        guard gameModel.selectedCharacter == nil else { return }
        resetSelectedCharacter(uuidString: defaults.string(forKey: GameStorageKeys.lastPlayerUUID) ?? "")
    }
}

// MARK: - Master Control Game

extension GameRoot {
    func startMaster(supporterTier: SupporterTier = .none) async {
        // Checked and set before the first suspension: a call that arrives while a start is
        // running is ignored, it neither starts a second game nor stops the one being started.
        // A start of either kind blocks the other: a Siri join racing a master start used to
        // tear the other down.
        guard !isStartingMaster, !isStartingGame else { return }
        isStartingMaster = true
        defer { isStartingMaster = false }
        await awaitInFlightStop()
        let generation = stopGeneration
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
        installAudioCoordinatorChangeHandler()

        await adventureRoot.adventureGameControllable.startGame(with: id)
        guard generation == stopGeneration else { return }
        gameModel.playerController = PlayerController(root: self, asGameMaster: true)
        gameModel.masterController = MasterController(root: self, asProxy: false)
        gameModel.tablePlayers = adventureRoot.adventureGameControllable.tablePlayers(for: id)

        gameModel.gameConfig.state = .started
        adventureRoot.startGame()

        await beginStatisticsSession(for: .master, at: gameModel.startGameTime)

        await gameModel.masterController?.start()
        if !gameModel.tablePlayers.isEmpty {
            // The table players' pins wait for the first shown map like a joined player's.
            await gameModel.masterController?.resetPlayers()
        }
        await diceRoot.diceGameControllable.setFocusDice(on: adventureRoot.adventureGameControllable.focusDice(for: id))
        guard generation == stopGeneration else { return }
#if !os(tvOS)
        adventureRoot.donateStartGame(of: id)
#endif

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
        guard !isStartingGame, !isStartingMaster else {
            Logger.networking.info("GameRoot: startGame ignored, another start is still running")
            return
        }
        isStartingGame = true
        defer { isStartingGame = false }
        let generation = stopGeneration
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
            supporterTier: supporterTier,
            companions: mode == .player ? Self.storedCompanions(for: gameModel.selectedCharacter) : []
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
            installAudioCoordinatorChangeHandler()
        }

        await adventureRoot.adventureGameControllable.resetGame()
        guard generation == stopGeneration else { return }
        #if os(visionOS)
        gameModel.shareState.isMaster = false
        #endif
        // Game mode before the player controller can process anything: a package the master
        // sends while connecting was written to the permanent library otherwise. A failed start
        // resets it again in `stopGame()`. See CODE_AUDIT_Folder §5.25.
        adventureRoot.startGame()
        let player = PlayerController(root: self, asGameMaster: mode == .demo)
        gameModel.playerController = player

        if mode == .demo {
            await joinGame(for: mode, supporterTier: supporterTier)

#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = true
#endif
        } else if await player.start(to: model, joinCode: joinCode) {
            // A stop during the connect already tore the game down.
            guard generation == stopGeneration else { return }
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
        let companions = type == .player ? Self.storedCompanions(for: gameModel.selectedCharacter) : []
        // Update the local player by id, not by index: a master broadcast
        // processed during connect can already have replaced the roster, and
        // index 0 may then be another player's entry.
        if let index = gameModel.gameRoster.players.firstIndex(where: { $0.id == gameModel.gameConfig.id }) {
            gameModel.gameRoster.players[index].type = type
            gameModel.gameRoster.players[index].name = name(for: type)
            gameModel.gameRoster.players[index].characterId = gameModel.selectedCharacter
            gameModel.gameRoster.players[index].supporterTier = supporterTier
            gameModel.gameRoster.players[index].companions = companions
        } else {
            gameModel.gameRoster.players.append(
                PlayerGameModel(
                    id: gameModel.gameConfig.id,
                    type: type,
                    name: name(for: type),
                    characterId: gameModel.selectedCharacter,
                    supporterTier: supporterTier,
                    companions: companions
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
        stopGeneration += 1
        // Coalesce concurrent callers onto the single in-flight teardown instead of running
        // it twice (or racing a fresh `startGame` — see `awaitInFlightStop()`).
        if let stopGameTask {
            await stopGameTask.value
            return
        }
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performStopGame()
            // Cleared by the teardown itself, without a suspension after it ended: a caller that
            // resumed late used to clear the task of a later stop, or leave a finished one that a
            // later `stopGame` coalesced onto without tearing anything down.
            if stopGameTaskToken == token {
                stopGameTask = nil
                stopGameTaskToken = nil
            }
        }
        stopGameTask = task
        stopGameTaskToken = token
        await task.value
    }

    private func awaitInFlightStop() async {
        await stopGameTask?.value
    }

    /// A media-services reset replaces the audio engine and its playback coordinator: the
    /// SharePlay controller must coordinate the new one, or the players hear nothing for the rest
    /// of the session. See CODE_AUDIT_Audio2 §5.9.
    private func installAudioCoordinatorChangeHandler() {
        audioRoot.setAudioCoordinatorChangeHandler { [weak self] coordinator in
            self?.networkStore.sharePlayStore.setup(audioCoordinator: coordinator)
        }
    }

    private func performStopGame() async {
        cancelOwnedTasks()
        audioRoot.setAudioCoordinatorChangeHandler(nil)
        mapRoot.mapGameControllable.resetBattleRound()
        battleRoundBroadcastLog.reset()
        await statisticsModel.checkpoint(participants: currentStatisticParticipants())
        await statisticsModel.finishSession()
        gameModel.playerGameStarted = false
        gameModel.gameConfig.state = .stopped
        // Guests of the 3D table belong to the game that ends here. See CODE_AUDIT_21 §5.12.
        gameModel.tableGuests = [:]
        gameModel.tableGuestMasterId = nil
        await gameModel.masterController?.stop()
        gameModel.masterController = nil
        await gameModel.playerController?.stop()
        gameModel.playerController?.uninstallMapPhotoActions()
        gameModel.playerController = nil
        // Only now: a message built while the controllers were stopping (a pending receipt, a
        // debounced value update) must not go out under the empty config's random master id.
        // See CODE_AUDIT_Game_Shareplay §5.25.
        gameModel.gameConfig = .empty
        await adventureRoot.adventureGameControllable.resetGame()
        // Bytes peers sent for files not downloaded here are only for the running game.
        FileUrlDataController.releaseHeldPeerData()
        // Other apps' audio may resume once the game's audio is not playing.
        audioRoot.releaseAudioSession()
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
    private nonisolated static let demoRevealPace: Duration = .seconds(3)
    /// Pacing before revealing each weather or map in the demo sequence — longer than
    /// `demoRevealPace` since these are bigger visual changes to let settle.
    /// See CODE_AUDIT §9.14.
    private nonisolated static let demoBigRevealPace: Duration = .seconds(5)

    func startDemo(supporterTier: SupporterTier = .none) async {
        // Cancel any previous demo loop before swapping `playerController` out from under it —
        // otherwise a still-running old task keeps sending reveal/mapState messages through its
        // own captured (now orphaned) controller, racing the new demo loop. See CODE_AUDIT.md §3.2.
        demoTask?.cancel()
        await startGame(to: nil, mode: .demo, supporterTier: supporterTier)

        guard let playerController = gameModel.playerController else { return }
        // `self` is bound strongly only for one step at a time, never across the paced
        // sleeps, so a missed teardown no longer keeps the root alive. See CODE_AUDIT_19 §3.11.
        demoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard var steps = self?.demoRoundSteps(), !steps.isEmpty else { return }
                while !steps.isEmpty {
                    let step = steps.removeFirst()
                    do {
                        try await Task.sleep(for: step.pace)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, let followUp = await self?.performDemoStep(step, playerController: playerController) else { return }
                    steps.insert(contentsOf: followUp, at: 0)
                }
            }
        }
    }

    private enum DemoStep {
        case photo(UUID)
        case weather(UUID)
        case map(UUID)
        case mapState(UUID, data: NetworkCodableDataType, isLast: Bool)

        var pace: Duration {
            switch self {
            case .photo, .mapState: GameRoot.demoRevealPace
            case .weather, .map: GameRoot.demoBigRevealPace
            }
        }
    }

    /// One demo round: every photo, then every weather, then every map. `nil` once the game
    /// stopped; empty when there is nothing to show (no step would ever suspend).
    private func demoRoundSteps() -> [DemoStep]? {
        guard gameModel.gameConfig.state != .stopped else { return nil }
        let photos = photoRoot.itemControllable.itemDataModel.items.map(DemoStep.photo)
        let weathers = weatherRoot.itemControllable.itemDataModel.items.map(DemoStep.weather)
        let maps = mapRoot.itemControllable.itemDataModel.items.map(DemoStep.map)
        return photos + weathers + maps
    }

    /// Sends one demo step and returns the steps that must follow it right away (a revealed
    /// map's state updates).
    private func performDemoStep(_ step: DemoStep, playerController: PlayerController) async -> [DemoStep] {
        let gameNetworkModel: GameNetworkModel
        var followUp: [DemoStep] = []
        switch step {
        case .photo(let id):
            let data = await photoRoot.gameControllable.share(id: id)
            gameNetworkModel = gameModel.outgoingMessage(counter: 1, type: .reveal, subType: .show, asMaster: true, data: data)
        case .weather(let id):
            let data = await weatherRoot.gameControllable.share(id: id)
            gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .reveal, subType: .show, asMaster: true, data: data)
        case .map(let id):
            let data = await mapRoot.mapGameControllable.shareMap(id: id)
            gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .reveal, subType: .show, asMaster: true, data: data)
            followUp = nextDemoMapState(for: id)
        case .mapState(let id, let data, let isLast):
            gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .update, subType: .mapState, asMaster: true, data: data)
            if !isLast {
                followUp = nextDemoMapState(for: id)
            }
        }
        await playerController.receivedProcess(gameNetworkModel)
        return followUp
    }

    /// The map's next demo state; after the last one the map is restarted once and the demo
    /// moves on.
    private func nextDemoMapState(for id: UUID) -> [DemoStep] {
        if let data = mapRoot.mapGameControllable.demoNextMap(itemId: id, restart: false) {
            return [.mapState(id, data: data, isLast: false)]
        }
        guard let data = mapRoot.mapGameControllable.demoNextMap(itemId: id, restart: true) else { return [] }
        return [.mapState(id, data: data, isLast: true)]
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
