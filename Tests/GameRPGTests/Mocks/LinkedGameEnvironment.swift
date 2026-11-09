// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AdventureRPG
@testable import GameRPG

/// A real game master and real players joined by an in-memory local network.
///
/// Every message a controller sends is encoded, handed to the other side's network controller
/// and decoded there, exactly like on a connection. The link records what crossed it, per
/// connection, so a test can say which player got bytes and which only a reference.
@MainActor
final class LinkedGameEnvironment {
    struct Player {
        let controller: PlayerController
        let root: GameRoot
        let config: GameConfigModel
        let connectionId: ConnectionController.ID

        var id: UUID { config.id }
    }

    let master: MasterController
    let masterRoot: GameRoot
    let masterConfig: GameConfigModel
    private(set) var players: [Player] = []
    private let masterStore: LinkedMasterStore
    private var networks: [GameNetworkController] = []

    /// Every message the master sent, with the connection it was addressed to (`nil` for a
    /// message to all connections).
    var masterSends: [(connectionId: ConnectionController.ID?, message: GameNetworkModel)] {
        masterStore.sends
    }

    /// Every message a player sent to the master, with the connection it came from.
    var playerSends: [(connectionId: ConnectionController.ID, message: GameNetworkModel)] {
        masterStore.received
    }

    private init(master: MasterController, masterRoot: GameRoot, masterConfig: GameConfigModel, masterStore: LinkedMasterStore) {
        self.master = master
        self.masterRoot = masterRoot
        self.masterConfig = masterConfig
        self.masterStore = masterStore
    }

    static func create() async throws -> LinkedGameEnvironment {
        let masterStore = LinkedMasterStore()
        let masterNetwork = GameNetworkController(
            name: "Master Link",
            proxy: false,
            masterBuilder: { _, _ in masterStore },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        masterStore.masterNetwork = masterNetwork

        let masterRoot = try await makeRoot(network: masterNetwork, name: "Master Proxy Link")
        let masterId = UUID()
        let masterConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Andrenalin")
        )
        masterRoot.gameModel.reset(gameConfig: masterConfig)
        let master = MasterController(root: masterRoot, asProxy: false)

        let environment = LinkedGameEnvironment(
            master: master,
            masterRoot: masterRoot,
            masterConfig: masterConfig,
            masterStore: masterStore
        )
        environment.networks.append(masterNetwork)
        return environment
    }

    /// Adds a player on a connection of its own. The player has not announced itself yet:
    /// call `ready(_:)` for the connect handshake (lists and Character).
    @discardableResult
    func addPlayer(named name: String) async throws -> Player {
        let connectionId = ConnectionController.ID()
        let playerStore = LinkedPlayerStore(connectionId: connectionId, masterStore: masterStore)
        let playerNetwork = GameNetworkController(
            name: "\(name) Link",
            proxy: false,
            masterBuilder: { _, _ in MasterNetworkControllableMock() },
            playerBuilder: { _, _ in playerStore }
        )
        masterStore.playerNetworks[connectionId] = playerNetwork

        let playerRoot = try await Self.makeRoot(network: playerNetwork, name: "\(name) Proxy Link")
        let playerId = UUID()
        let config = GameConfigModel(id: playerId, state: .started, master: .empty)
        playerRoot.gameModel.reset(
            gameConfig: config,
            gameRoster: GameRosterModel(players: [PlayerGameModel(id: playerId, type: .player, name: name)])
        )
        let controller = PlayerController(root: playerRoot, asGameMaster: false)

        let player = Player(controller: controller, root: playerRoot, config: config, connectionId: connectionId)
        players.append(player)
        networks.append(playerNetwork)
        return player
    }

    /// The connect handshake of a player: the connection becomes ready on both ends.
    func ready(_ player: Player) async {
        await masterStore.masterNetwork?.masterReady(for: player.connectionId)
        await masterStore.playerNetworks[player.connectionId]?.playerReady()
    }

    /// Waits until the master and every player have handled all they were sent, including the
    /// replies that handling caused. A reply sent while a worker is busy is queued behind the
    /// current message and its sender returns at once, so the call that started a flow returns
    /// before the flow has ended. Fails the test when the links do not settle.
    func settle(timeout: Duration = .seconds(10), sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = ContinuousClock.now + timeout
        while !(await isSettled) {
            guard ContinuousClock.now < deadline else {
                Issue.record("The linked game did not settle", sourceLocation: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private var isSettled: Bool {
        get async {
            guard await master.messagePipeline.isIdle else { return false }
            for player in players where await !player.controller.messagePipeline.isIdle {
                return false
            }
            return true
        }
    }

    func clearHistory() {
        masterStore.sends.removeAll()
        masterStore.received.removeAll()
    }

    /// The messages the master sent that reached `player`: its own and those for everyone.
    func deliveries(to player: Player) -> [GameNetworkModel] {
        masterSends.filter { $0.connectionId == nil || $0.connectionId == player.connectionId }.map(\.message)
    }

    private static func makeRoot(network: GameNetworkController, name: String) async throws -> GameRoot {
        let root = try await MockRoot.createGameRoot()
        try await MockRoot.resetTestData(for: root.adventureRoot)
        try await MockRoot.resetGameController(for: root)
        root.networkStore = network
        root.networkProxyStore = GameNetworkController(
            name: name,
            proxy: true,
            masterBuilder: { _, _ in MasterNetworkControllableMock() },
            playerBuilder: { _, _ in PlayerStoreAbstractionMock() }
        )
        return root
    }
}

extension LinkedGameEnvironment {
    func importData(named resource: String, into root: GameRoot) async throws {
        let url = ResourcesDebug.bundle.url(forResource: resource, withExtension: "gmz").unsafelyUnwrapped
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        _ = try await task.value
    }
}

/// The master's end of the link: relays to the players' network controllers and records.
private final class LinkedMasterStore: MasterNetworkControllable, @unchecked Sendable {
    @MainActor let networkModel: MasterNetworkModel
    weak var masterNetwork: GameNetworkController?
    var playerNetworks: [ConnectionController.ID: GameNetworkController] = [:]
    var sends: [(connectionId: ConnectionController.ID?, message: GameNetworkModel)] = []
    var received: [(connectionId: ConnectionController.ID, message: GameNetworkModel)] = []

    @MainActor
    init() {
        networkModel = MasterNetworkModel(name: "Linked Master")
    }

    @MainActor func startStreaming(passcode: String) {}
    @MainActor func stopStreaming() {}
    @MainActor func toggleStreaming(passcode: String) {}
    @MainActor func startProxyStreaming(passcode: String) {}

    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool {
        guard let network = playerNetworks[id] else { return false }
        await deliver(data, to: [(id, network)], addressedTo: id)
        return true
    }

    func sendResponse(data: MessageMapper?) async {
        await deliver(data, to: playerNetworks.map { ($0.key, $0.value) }, addressedTo: nil)
    }

    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async {
        for (id, network) in playerNetworks where id != except {
            await deliver(data, to: [(id, network)], addressedTo: id)
        }
    }

    private func deliver(
        _ data: MessageMapper?,
        to networks: [(ConnectionController.ID, GameNetworkController)],
        addressedTo connectionId: ConnectionController.ID?
    ) async {
        let bytes = data?.encodeData()
        if let message = GameNetworkModel.decodeData(of: bytes) {
            sends.append((connectionId, message))
        }
        for (_, network) in networks {
            await network.playerReceived(data: bytes)
        }
    }

    func receive(_ data: MessageMapper?, from connectionId: ConnectionController.ID) async {
        let bytes = data?.encodeData()
        if let message = GameNetworkModel.decodeData(of: bytes) {
            received.append((connectionId, message))
        }
        await masterNetwork?.masterReceived(data: bytes, for: connectionId)
    }
}

/// A player's end of the link.
private final class LinkedPlayerStore: PlayerNetworkControllable, @unchecked Sendable {
    @MainActor let networkModel: PlayerNetworkModel
    let browserManager: BrowserManager
    let connectionId: ConnectionController.ID
    let masterStore: LinkedMasterStore

    @MainActor
    init(connectionId: ConnectionController.ID, masterStore: LinkedMasterStore) {
        self.networkModel = PlayerNetworkModel(name: "Linked Player")
        self.browserManager = BrowserManager()
        self.connectionId = connectionId
        self.masterStore = masterStore
    }

    @MainActor func toggleConnection(to _: BrowserGameModel, passcode: String) async -> Bool { true }
    @MainActor func stop() async {}

    func request(with content: MessageMapper?) async {
        await masterStore.receive(content, from: connectionId)
    }
}
#endif
