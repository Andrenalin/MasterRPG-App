// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import RPGResourcesDebug
import Testing

@testable import CoreRPG
@testable import GameRPG
@testable import MapRPG
@testable import PhotoRPG
@testable import WeatherRPG
import AdventureRPG

@Suite("Photo shown over the map")
@MainActor
struct MapPhotoPresentationTests {
    private static let sessionId = UUID()

    private static func presentation(
        itemId: UUID = UUID(),
        module: NetworkModules = .photo,
        mapId: UUID = UUID(),
        mode: MapPhotoMode = .popover,
        sequence: Int,
        sessionId: UUID = sessionId
    ) -> MapPhotoPresentation {
        MapPhotoPresentation(
            itemId: itemId,
            module: module,
            mapId: mapId,
            anchor: CGPoint(x: 10, y: 20),
            mode: mode,
            sequence: sequence,
            sessionId: sessionId
        )
    }

    private static func masterConfig() -> GameConfigModel {
        let id = UUID()
        return GameConfigModel(id: id, state: .started, master: MasterGameModel(id: id, type: .master, name: "Game Master"))
    }

    // MARK: - State

    @Test("A master change wins over a local one; a local one stays until the next master change")
    func masterChangeWinsOverLocal() {
        var state = MapPhotoPresentationState()
        let first = Self.presentation(sequence: 1)
        let result1 = state.applyMaster(first)
        #expect(result1)
        #expect(state.mode == .popover)
        #expect(state.presentation == first)

        let result2 = state.setLocal(.closed)
        #expect(result2)
        #expect(state.mode == .closed)
        #expect(!state.isActive)
        // The echo of the same master change does not reopen it.
        let result3 = state.applyMaster(first)
        #expect(!result3)
        #expect(state.mode == .closed)

        let result4 = state.applyMaster(first.changed(to: .fullScreen, sequence: 2))
        #expect(result4)
        #expect(state.mode == .fullScreen)
    }

    @Test("An older master change is ignored; a restarted game counts again")
    func sequenceOrdering() {
        var state = MapPhotoPresentationState()
        let photo = Self.presentation(sequence: 5)
        let result5 = state.applyMaster(photo)
        #expect(result5)
        let result6 = state.applyMaster(photo.changed(to: .closed, sequence: 4))
        #expect(!result6)
        #expect(state.mode == .popover)

        let restarted = Self.presentation(mode: .fullScreen, sequence: 1, sessionId: UUID())
        let result7 = state.applyMaster(restarted)
        #expect(result7)
        #expect(state.mode == .fullScreen)
    }

    @Test("Each switch to full screen is counted, for the visionOS viewer")
    func fullScreenRequestCounts() {
        var state = MapPhotoPresentationState()
        let photo = Self.presentation(sequence: 1)
        state.applyMaster(photo)
        #expect(state.fullScreenRequest == 0)
        // The mode alone counts nothing: the photo window opens when the item is current.
        state.setLocal(.fullScreen)
        state.setLocal(.popover)
        state.setLocal(.fullScreen)
        #expect(state.fullScreenRequest == 0)
        state.noteFullScreenShown()
        state.noteFullScreenShown()
        #expect(state.fullScreenRequest == 2)
        // A local change needs a presentation of the game master.
        state.reset()
        let result8 = state.setLocal(.popover)
        #expect(!result8)
    }

    @Test("A local presentation gives way to the game master's next change; closing keeps the order")
    func localPresentation() {
        var state = MapPhotoPresentationState()
        let master = Self.presentation(sequence: 3)
        let applied = state.applyMaster(master)
        #expect(applied)

        state.presentLocal(Self.presentation(mode: .fullScreen, sequence: 0, sessionId: UUID()))
        #expect(state.isLocal)
        #expect(state.mode == .fullScreen)

        // A late copy of the master's earlier change does not replace it.
        let stale = state.applyMaster(master)
        #expect(!stale)
        #expect(state.isLocal)

        state.clear()
        let afterClear = state.applyMaster(master)
        #expect(!afterClear)
        let newer = state.applyMaster(master.changed(to: .popover, sequence: 4))
        #expect(newer)
        #expect(!state.isLocal)
    }

    @Test("The presentation round-trips as a message payload naming its photo")
    func payloadRoundTrip() throws {
        let photo = Self.presentation(mode: .fullScreen, sequence: 3)
        let data = photo.networkData
        #expect(data.id == photo.itemId)
        #expect(data.type == .photo)
        #expect(try #require(MapPhotoPresentation.decodeData(of: data.data)) == photo)
    }

    @Test("A presentation message is no presentation, asset or asset request of its own")
    func messageShape() {
        let model = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .photoPresentation,
            gameConfig: Self.masterConfig(),
            data: Self.presentation(sequence: 1).networkData
        )
        #expect(!model.isPresentation)
        #expect(!model.carriesAsset)
        #expect(!model.isAssetRequest)
        #expect(!model.isPlayerGroupEvent)
    }

    // MARK: - Player

    private struct PlayerFixture {
        let env: PlayerControllerTestEnvironment
        let photoId: UUID
        let photoData: NetworkCodableDataType
        let mapId: UUID
        let masterConfig: GameConfigModel
    }

    private static func playerFixture() async throws -> PlayerFixture {
        let env = try await PlayerControllerTestEnvironment.create()
        try await MockRoot.importTestData(into: env.root.adventureRoot)
        env.root.adventureRoot.startGame()
        let photoId = env.root.photoRoot.itemControllable.itemDataModel.items[0]
        let photoData = try await env.root.photoRoot.gameControllable.createGameData(for: photoId)
        let map = MapModel(id: UUID(), name: "Dungeon")
        env.root.mapRoot.gameController.setGame(item: map.copy(), itemId: map.id)
        env.playerController.gameModel.setGameUpdateType(.map)
        return PlayerFixture(env: env, photoId: photoId, photoData: photoData, mapId: map.id, masterConfig: masterConfig())
    }

    private static func send(
        _ presentation: MapPhotoPresentation,
        counter: Int,
        to fixture: PlayerFixture
    ) async throws {
        _ = try await fixture.env.playerController.handle(GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .update,
            subType: .photoPresentation,
            gameConfig: fixture.masterConfig,
            data: presentation.networkData
        ))
    }

    private static func reveal(counter: Int, to fixture: PlayerFixture) async throws {
        _ = try await fixture.env.playerController.handle(GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: fixture.masterConfig,
            data: fixture.photoData
        ))
    }

    @Test("A photo the game master shows over the map opens in the popover; their changes follow")
    func playerFollowsMaster() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController
        let popover = fixture.env.root.mapRoot.photoPopover
        let shown = Self.presentation(itemId: fixture.photoId, mapId: fixture.mapId, sequence: 1)

        try await Self.send(shown, counter: 1, to: fixture)
        try await Self.reveal(counter: 2, to: fixture)
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo == MapPhotoPopoverItem(itemId: fixture.photoId, mapId: fixture.mapId, anchor: shown.anchor))

        try await Self.send(shown.changed(to: .fullScreen, sequence: 2), counter: 3, to: fixture)
        #expect(player.gameModel.gameUpdateType == .photo)
        #expect(popover.photo == nil)
        #expect(fixture.env.root.photoRoot.photoGameControllable.presentedPhotoId == fixture.photoId)

        try await Self.send(shown.changed(to: .closed, sequence: 3), counter: 4, to: fixture)
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo == nil)
    }

    @Test("A player's own switch stays local until the game master changes the mode")
    func playerLocalSwitch() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController
        let popover = fixture.env.root.mapRoot.photoPopover
        let shown = Self.presentation(itemId: fixture.photoId, mapId: fixture.mapId, sequence: 1)
        try await Self.send(shown, counter: 1, to: fixture)
        try await Self.reveal(counter: 2, to: fixture)

        // The popover's Full Screen button, on a player's device: nothing is sent.
        let sentBefore = fixture.env.playerNetworkSpy.requestHistory.count
        popover.showFullScreen()
        #expect(player.gameModel.gameUpdateType == .photo)
        player.requestMapPhotoMode(.closed)
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo == nil)
        #expect(fixture.env.playerNetworkSpy.requestHistory.count == sentBefore)

        // The game master shows it full screen: everyone follows.
        try await Self.send(shown.changed(to: .fullScreen, sequence: 2), counter: 3, to: fixture)
        #expect(player.gameModel.gameUpdateType == .photo)
    }

    @Test("The photo window request counts only once the photo is current, never for a photo the player lacks")
    func fullScreenRequestFollowsCurrentItem() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController

        // A photo this player does not hold cannot become current: nothing opens.
        let unknown = Self.presentation(itemId: UUID(), mapId: fixture.mapId, mode: .fullScreen, sequence: 1)
        try await Self.send(unknown, counter: 1, to: fixture)
        #expect(player.gameModel.mapPhoto.mode == .fullScreen)
        #expect(player.gameModel.mapPhoto.fullScreenRequest == 0)
        #expect(player.gameModel.gameUpdateType == .map)

        // A held photo is made current first, then counted once.
        let known = Self.presentation(itemId: fixture.photoId, mapId: fixture.mapId, mode: .fullScreen, sequence: 2)
        try await Self.send(known, counter: 2, to: fixture)
        #expect(await awaitCondition { player.gameModel.gameUpdateType == .photo })
        #expect(player.gameModel.mapPhoto.fullScreenRequest == 1)

        // A photo that arrives for no waiting presentation changes nothing.
        player.applyWaitingMapPhoto(itemId: UUID())
        #expect(player.gameModel.mapPhoto.fullScreenRequest == 1)
    }

    @Test("After a lost connection the popover is gone, and Close removes a stale one")
    func lostConnectionClearsPopover() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController
        let popover = fixture.env.root.mapRoot.photoPopover
        let shown = Self.presentation(itemId: fixture.photoId, mapId: fixture.mapId, sequence: 1)
        try await Self.send(shown, counter: 1, to: fixture)
        try await Self.reveal(counter: 2, to: fixture)
        #expect(popover.photo != nil)

        await player.lostConnection()

        #expect(player.gameModel.mapPhoto.presentation == nil)
        #expect(popover.photo == nil)

        // A popover that outlived its presentation anyway closes with the Close button.
        popover.photo = MapPhotoPopoverItem(itemId: fixture.photoId, mapId: fixture.mapId, anchor: .zero)
        player.requestMapPhotoMode(.closed)
        #expect(popover.photo == nil)
    }

    @Test("Without a presentation, or for another map, a photo is shown full screen as before")
    func photoWithoutMapPresentation() async throws {
        let fixture = try await Self.playerFixture()
        try await Self.reveal(counter: 1, to: fixture)
        #expect(fixture.env.playerController.gameModel.gameUpdateType == .photo)
        #expect(fixture.env.root.mapRoot.photoPopover.photo == nil)

        let otherMap = Self.presentation(itemId: fixture.photoId, mapId: UUID(), sequence: 1)
        fixture.env.playerController.gameModel.setGameUpdateType(.map)
        try await Self.send(otherMap, counter: 2, to: fixture)
        try await Self.reveal(counter: 3, to: fixture)
        #expect(fixture.env.playerController.gameModel.gameUpdateType == .photo)
        #expect(fixture.env.root.mapRoot.photoPopover.photo == nil)
        #expect(fixture.env.playerController.gameModel.mapPhoto.presentation == nil)
    }

    @Test("Showing anything else closes the photo on the map; a live state of its map keeps it")
    func otherPresentationClosesMapPhoto() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController
        let shown = Self.presentation(itemId: fixture.photoId, mapId: fixture.mapId, sequence: 1)
        try await Self.send(shown, counter: 1, to: fixture)
        try await Self.reveal(counter: 2, to: fixture)

        player.noteMasterPresentation(type: .update, module: .map, itemId: fixture.mapId)
        #expect(fixture.env.root.mapRoot.photoPopover.photo != nil)
        player.noteMasterPresentation(type: .update, module: .photo, itemId: UUID())
        #expect(fixture.env.root.mapRoot.photoPopover.photo != nil)
        player.noteMasterPresentation(type: .update, module: .weather, itemId: UUID())
        #expect(fixture.env.root.mapRoot.photoPopover.photo != nil)

        player.noteMasterPresentation(type: .reveal, module: .pdf, itemId: UUID())
        #expect(fixture.env.root.mapRoot.photoPopover.photo == nil)
        #expect(player.gameModel.mapPhoto.presentation == nil)
    }

    @Test("A player's pin photo goes full screen on their device only, and back onto the map at the pin")
    func playerPinPhotoFullScreen() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController
        let popover = fixture.env.root.mapRoot.photoPopover
        let sentBefore = fixture.env.playerNetworkSpy.requestHistory.count
        let pin = MapPhotoPopoverItem(
            itemId: fixture.photoId,
            mapId: fixture.mapId,
            anchor: CGPoint(x: 30, y: 40),
            title: "Goblin"
        )

        // The pin popover's Full Screen button, shared or not: a player never sends.
        popover.actions?.showPhotoFullScreen(pin, true)
        #expect(await awaitCondition { player.gameModel.gameUpdateType == .photo })
        #expect(player.gameModel.mapPhoto.isLocal)
        #expect(fixture.env.root.photoRoot.gameControllable.gameModel.currentItemId == fixture.photoId)

        player.requestMapPhotoMode(.popover)
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo == pin)
        #expect(fixture.env.playerNetworkSpy.requestHistory.count == sentBefore)
    }

    // MARK: - Weather

    private static func weatherData(in fixture: PlayerFixture, name: String) async throws -> NetworkCodableDataType {
        let weatherRoot = fixture.env.root.weatherRoot
        let weatherId = await weatherRoot.itemController.addNew(type: .scenario)
        weatherRoot.editController.reset(name: name, itemId: weatherId, forceSave: false)
        return try await weatherRoot.weatherGameControllable.createWeatherGameData(for: weatherId)
    }

    @Test("A weather the game master shows over the map opens in the popover with its name; full screen shows the weather")
    func playerWeatherOnMap() async throws {
        let fixture = try await Self.playerFixture()
        let player = fixture.env.playerController
        let popover = fixture.env.root.mapRoot.photoPopover
        let weather = try await Self.weatherData(in: fixture, name: "Storm front")
        let shown = Self.presentation(itemId: weather.id, module: .weather, mapId: fixture.mapId, sequence: 1)
        var titled = shown
        titled.title = "Storm front"

        try await Self.send(titled, counter: 1, to: fixture)
        _ = try await player.handle(GameNetworkModel(
            counter: 2,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: fixture.masterConfig,
            data: weather
        ))
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo == MapPhotoPopoverItem(
            itemId: weather.id,
            module: .weather,
            mapId: fixture.mapId,
            anchor: titled.anchor,
            title: "Storm front"
        ))

        let windowRequests = player.gameModel.weatherWindowRequest
        try await Self.send(titled.changed(to: .fullScreen, sequence: 2), counter: 3, to: fixture)
        #expect(player.gameModel.gameUpdateType == .weather)
        #expect(popover.photo == nil)
        // visionOS opens the weather window for it.
        #expect(player.gameModel.weatherWindowRequest == windowRequests + 1)

        // A player's own Show on Map stays on this device.
        player.requestMapPhotoMode(.popover)
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo?.module == .weather)

        try await Self.send(titled.changed(to: .closed, sequence: 3), counter: 4, to: fixture)
        #expect(player.gameModel.gameUpdateType == .map)
        #expect(popover.photo == nil)
    }

    @Test("Without a presentation a weather is shown full screen as before")
    func weatherWithoutMapPresentation() async throws {
        let fixture = try await Self.playerFixture()
        let weather = try await Self.weatherData(in: fixture, name: "Fog")
        _ = try await fixture.env.playerController.handle(GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            gameConfig: fixture.masterConfig,
            data: weather
        ))
        #expect(fixture.env.playerController.gameModel.gameUpdateType == .weather)
        #expect(fixture.env.playerController.gameModel.weatherWindowRequest == 1)
        #expect(fixture.env.root.mapRoot.photoPopover.photo == nil)
    }

    @Test("The game master presents a weather on the map with the weather's name")
    func masterPresentsWeatherOverMap() async throws {
        let fixture = try await Self.playerFixture()
        let root = fixture.env.root
        root.gameModel.playerController = fixture.env.playerController
        let master = MasterController(root: root, asProxy: false)
        let weather = try await Self.weatherData(in: fixture, name: "Storm front")

        let presentation = try #require(master.newMapPhotoPresentation(for: .weather, itemId: weather.id))
        #expect(presentation.module == .weather)
        #expect(presentation.title == "Storm front")
        #expect(presentation.mode == .popover)
        #expect(presentation.networkData.type == .weather)
        // Other modules are never shown on the map.
        #expect(master.newMapPhotoPresentation(for: .pdf, itemId: UUID()) == nil)
    }

    // MARK: - Master

    @Test("The game master presents a photo on the map only while the map is on screen")
    func masterPresentsOnlyOverMap() async throws {
        let fixture = try await Self.playerFixture()
        let root = fixture.env.root
        root.gameModel.playerController = fixture.env.playerController
        let master = MasterController(root: root, asProxy: false)

        let presentation = try #require(master.newMapPhotoPresentation(for: .photo, itemId: fixture.photoId))
        #expect(presentation.mapId == fixture.mapId)
        #expect(presentation.mode == .popover)
        // No room opened: the map's center (1200 × 800 by default).
        #expect(presentation.anchor == CGPoint(x: 600, y: 400))
        let next = try #require(master.newMapPhotoPresentation(for: .photo, itemId: fixture.photoId))
        #expect(next.sequence > presentation.sequence)

        fixture.env.playerController.gameModel.setGameUpdateType(.pdf)
        #expect(master.newMapPhotoPresentation(for: .photo, itemId: fixture.photoId) == nil)
    }

    @Test("The game master's pin photo goes full screen for everyone only for a pin the players see")
    func masterPinPhotoFullScreen() async throws {
        let fixture = try await Self.playerFixture()
        let root = fixture.env.root
        let masterConfig = Self.masterConfig()
        root.gameModel.reset(gameConfig: masterConfig, gameRoster: GameRosterModel(players: []))
        let masterPlayer = PlayerController(root: root, asGameMaster: true)
        root.gameModel.playerController = masterPlayer
        root.gameModel.masterController = MasterController(root: root, asProxy: false)
        masterPlayer.gameModel.setGameUpdateType(.map)
        let pin = MapPhotoPopoverItem(itemId: fixture.photoId, mapId: fixture.mapId, anchor: .zero, title: "Goblin")

        // A hidden pin: only on the game master's device, and its changes stay there.
        root.mapRoot.photoPopover.actions?.showPhotoFullScreen(pin, false)
        #expect(masterPlayer.gameModel.mapPhoto.isLocal)
        // The shared screen (late-joiner replay, external display) stays the map, never the
        // private photo.
        #expect(masterPlayer.gameModel.sharedUpdateType == .map)
        masterPlayer.requestMapPhotoMode(.popover)
        #expect(root.mapRoot.photoPopover.isPrivate)
        #expect(masterPlayer.gameModel.sharedUpdateType == .map)
        masterPlayer.requestMapPhotoMode(.closed)
        #expect(masterPlayer.gameModel.mapPhoto.isLocal)
        #expect(masterPlayer.gameModel.sharedUpdateType == .map)
        #expect(await root.gameModel.masterController?.replayMapPhoto(to: .direct(nil)) == false)

        // A pin the players see: a master presentation, so the replay carries it.
        root.mapRoot.photoPopover.actions?.showPhotoFullScreen(pin, true)
        #expect(!masterPlayer.gameModel.mapPhoto.isLocal)
        #expect(masterPlayer.gameModel.mapPhoto.mode == .fullScreen)
        #expect(masterPlayer.gameModel.mapPhoto.presentation?.title == "Goblin")
        #expect(await awaitCondition { masterPlayer.gameModel.gameUpdateType == .photo })

        // Closing the pin's popover broadcast the map state; its echo on the game master's own
        // screen must not take the full-screen photo away.
        _ = try await masterPlayer.handle(GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .mapState,
            gameConfig: masterConfig,
            data: NetworkCodableDataType(id: fixture.mapId, type: .map, version: 0, data: Data())
        ))
        #expect(masterPlayer.gameModel.gameUpdateType == .photo)

        masterPlayer.requestMapPhotoMode(.closed)
        #expect(masterPlayer.gameModel.gameUpdateType == .map)
    }

    @Test("A paused \"Share Map\" keeps the game master's pin photo on their device (§6.2)")
    func pausedSharingKeepsPinPhotoLocal() async throws {
        let fixture = try await Self.playerFixture()
        let root = fixture.env.root
        root.gameModel.reset(gameConfig: Self.masterConfig(), gameRoster: GameRosterModel(players: []))
        let masterPlayer = PlayerController(root: root, asGameMaster: true)
        root.gameModel.playerController = masterPlayer
        root.gameModel.masterController = MasterController(root: root, asProxy: false)
        masterPlayer.gameModel.setGameUpdateType(.map)
        let pin = MapPhotoPopoverItem(itemId: fixture.photoId, mapId: fixture.mapId, anchor: CGPoint(x: 5, y: 6), title: "Goblin")

        root.mapRoot.rootModel.isMapStreaming = false
        root.mapRoot.photoPopover.actions?.showPhotoFullScreen(pin, true)

        #expect(masterPlayer.gameModel.mapPhoto.isLocal, "nothing with the pin's name and position goes out")
        #expect(masterPlayer.gameModel.sharedUpdateType == .map)
        #expect(await root.gameModel.masterController?.replayMapPhoto(to: .direct(nil)) == false)

        root.mapRoot.rootModel.isMapStreaming = true
        root.mapRoot.photoPopover.actions?.showPhotoFullScreen(pin, true)
        #expect(!masterPlayer.gameModel.mapPhoto.isLocal)
    }

    @Test("A live map update keeps a full-screen photo over that map; another map's update does not")
    func liveMapUpdateKeepsFullScreenPhoto() {
        let model = PlayerControllerModel()
        let mapId = UUID()
        model.mapPhoto.applyMaster(Self.presentation(mapId: mapId, mode: .fullScreen, sequence: 1))
        model.setGameUpdateType(.photo)

        model.showMapForLiveUpdate(of: mapId)
        #expect(model.gameUpdateType == .photo)
        model.showMapForLiveUpdate(of: UUID())
        #expect(model.gameUpdateType == .map)

        model.setGameUpdateType(.photo)
        model.mapPhoto.setLocal(.closed)
        model.showMapForLiveUpdate(of: mapId)
        #expect(model.gameUpdateType == .map)
    }

    @Test("The game master ignores a presentation sent by a player")
    func masterIgnoresPlayerPresentation() async throws {
        let fixture = try await Self.playerFixture()
        let master = MasterController(root: fixture.env.root, asProxy: false)
        let playerConfig = GameConfigModel(
            id: UUID(),
            state: .started,
            master: MasterGameModel(id: UUID(), type: .master, name: "Game Master")
        )
        let result = try await master.handlePhoto(GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .photoPresentation,
            gameConfig: playerConfig,
            data: Self.presentation(itemId: fixture.photoId, sequence: 1).networkData
        ))
        #expect(result == nil)
    }
}
#endif
