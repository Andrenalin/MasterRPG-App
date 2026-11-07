// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import GameRPG
@testable import PhotoRPG
@testable import WeatherRPG

/// The weather the game master shows also covers every 3D table, until the game master shows
/// another, clears it or the game ends.
@Suite("Weather on the 3D table", .serialized)
@MainActor
struct TableWeatherTests {
    private static func presentation(
        weatherId: UUID = UUID(),
        isShown: Bool = true,
        sequence: Int,
        sessionId: UUID = sessionId
    ) -> TableWeatherPresentation {
        TableWeatherPresentation(weatherId: weatherId, isShown: isShown, sequence: sequence, sessionId: sessionId)
    }

    private static let sessionId = UUID()

    // MARK: - State

    @Test("A shown weather waits until this device holds it; an older change is ignored")
    func stateOrdering() {
        var state = TableWeatherState()
        let storm = UUID()
        let fog = UUID()

        let applied1 = state.applyMaster(Self.presentation(weatherId: storm, sequence: 1), isHeld: false)
        #expect(applied1)
        #expect(state.shownWeatherId == storm)
        #expect(state.visibleWeatherId == nil)
        state.weatherArrived(fog)
        #expect(state.visibleWeatherId == nil)
        state.weatherArrived(storm)
        #expect(state.visibleWeatherId == storm)

        let applied2 = state.applyMaster(Self.presentation(weatherId: fog, sequence: 2), isHeld: true)
        #expect(applied2)
        #expect(state.visibleWeatherId == fog)
        // A late copy of the first change does not bring the storm back.
        let applied3 = state.applyMaster(Self.presentation(weatherId: storm, sequence: 1), isHeld: true)
        #expect(!applied3)
        #expect(state.visibleWeatherId == fog)

        let applied4 = state.applyMaster(Self.presentation(weatherId: fog, isShown: false, sequence: 3), isHeld: true)
        #expect(applied4)
        #expect(state.shownWeatherId == nil)
        #expect(state.visibleWeatherId == nil)
        // A weather that arrives after the clear stays off the table.
        state.weatherArrived(fog)
        #expect(state.visibleWeatherId == nil)

        // A restarted game counts from one again.
        let applied5 = state.applyMaster(Self.presentation(weatherId: storm, sequence: 1, sessionId: UUID()), isHeld: true)
        #expect(applied5)
        #expect(state.visibleWeatherId == storm)

        state.reset()
        #expect(state.presentation == nil)
        #expect(state.visibleWeatherId == nil)
    }

    @Test("The payload round-trips and its message is no presentation or asset")
    func payloadAndShape() throws {
        let presentation = Self.presentation(sequence: 4)
        let data = presentation.networkData
        #expect(data.id == presentation.weatherId)
        #expect(data.type == .weather)
        #expect(TableWeatherPresentation.decodeData(of: data.data) == presentation)

        let message = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .tableWeather,
            gameConfig: GameConfigModel(
                id: UUID(),
                state: .started,
                master: MasterGameModel(id: UUID(), type: .master, name: "Master")
            ),
            data: data
        )
        #expect(!message.isPresentation)
        #expect(!message.carriesAsset)
        #expect(!message.isAssetRequest)
    }

    // MARK: - Message flow

    @Test(
        "Showing a weather puts it on the table before its reveal; a player draws it once it arrives",
        .enabled(if: MasterController.isTableWeatherEnabled, "Table weather is not sent for now")
    )
    func showFlow() async throws {
        let fixture = try await Self.fixture()
        let env = fixture.environment
        let reference = await env.masterRoot.weatherRoot.weatherGameControllable.shareWeather(id: fixture.weatherId)
        let sentBefore = env.masterNetworkSpy.sendResponseHistory.count

        await env.master.show(for: reference)

        let sent = env.masterNetworkSpy.sendResponseHistory.dropFirst(sentBefore).compactMap { $0 as? GameNetworkModel }
        let tableIndex = try #require(sent.firstIndex { $0.type == .update && $0.subType == .tableWeather })
        let revealIndex = try #require(sent.firstIndex { $0.type == .reveal && $0.data.type == .weather })
        #expect(tableIndex < revealIndex)
        let tableMessage = sent[tableIndex]
        #expect(tableMessage.data.id == fixture.weatherId)

        // The player learns the table weather before it holds the weather.
        _ = try await env.player1.handleWeather(tableMessage)
        #expect(env.player1.gameModel.tableWeather.shownWeatherId == fixture.weatherId)
        #expect(env.player1.gameModel.tableWeather.visibleWeatherId == nil)

        // The reveal asks for the package; once it arrives the table draws the weather.
        let request = try #require(try await env.player1.handleWeather(sent[revealIndex]))
        #expect(request.isAssetRequest)
        var delivery = sent[revealIndex]
        delivery.data = try #require(try await env.master.handleWeather(request))
        _ = try await env.player1.handleWeather(delivery)
        #expect(env.player1.gameModel.tableWeather.visibleWeatherId == fixture.weatherId)
    }

    @Test(
        "The game master clears the weather from every table; a player cannot set one",
        .enabled(if: MasterController.isTableWeatherEnabled, "Table weather is not sent for now")
    )
    func clearAndSender() async throws {
        let fixture = try await Self.fixture()
        let env = fixture.environment
        let masterScreen = PlayerController(root: env.masterRoot, asGameMaster: true)
        env.masterRoot.gameModel.playerController = masterScreen

        let reference = await env.masterRoot.weatherRoot.weatherGameControllable.shareWeather(id: fixture.weatherId)
        await env.master.show(for: reference)
        let shown = try #require(Self.lastTableWeather(in: env))
        // The game master's own screen holds the weather in its library.
        _ = try await masterScreen.handleWeather(shown)
        #expect(masterScreen.gameModel.tableWeather.visibleWeatherId == fixture.weatherId)
        _ = try await env.player1.handleWeather(shown)
        env.player1.tableWeatherArrived(fixture.weatherId)
        #expect(env.player1.gameModel.tableWeather.visibleWeatherId == fixture.weatherId)

        await env.master.clearTableWeather()
        let cleared = try #require(Self.lastTableWeather(in: env))
        #expect(TableWeatherPresentation.decodeData(of: cleared.data.data)?.isShown == false)
        _ = try await masterScreen.handleWeather(cleared)
        _ = try await env.player1.handleWeather(cleared)
        #expect(masterScreen.gameModel.tableWeather.visibleWeatherId == nil)
        #expect(env.player1.gameModel.tableWeather.visibleWeatherId == nil)

        // A player's message naming a table weather changes nothing, on players or the master.
        let forged = env.player2Root.gameModel.outgoingMessage(
            counter: 99,
            type: .update,
            subType: .tableWeather,
            asMaster: false,
            data: Self.presentation(
                weatherId: fixture.weatherId,
                sequence: 99,
                sessionId: env.master.gameModel.deliverySessionId
            ).networkData
        )
        _ = try await env.player1.handleWeather(forged)
        #expect(env.player1.gameModel.tableWeather.shownWeatherId == nil)
        #expect(try await env.master.handleWeather(forged) == nil)
    }

    @Test(
        "A peer that joins late gets the weather's package and then the table weather",
        .enabled(if: MasterController.isTableWeatherEnabled, "Table weather is not sent for now")
    )
    func replay() async throws {
        let fixture = try await Self.fixture()
        let env = fixture.environment
        let masterScreen = PlayerController(root: env.masterRoot, asGameMaster: true)
        env.masterRoot.gameModel.playerController = masterScreen

        // Nothing on the table: nothing to replay.
        let before = env.masterNetworkSpy.sendResponseHistory.count
        await env.master.replayTableWeather(to: .direct(ConnectionController.ID()))
        #expect(env.masterNetworkSpy.sendResponseHistory.count == before)

        let reference = await env.masterRoot.weatherRoot.weatherGameControllable.shareWeather(id: fixture.weatherId)
        await env.master.show(for: reference)
        _ = try await masterScreen.handleWeather(try #require(Self.lastTableWeather(in: env)))

        let sentBefore = env.masterNetworkSpy.sendResponseHistory.count
        // To the joining peer's own connection, as `ready(for:)` replays.
        await env.master.replayTableWeather(to: .direct(ConnectionController.ID()))
        let replayed = env.masterNetworkSpy.sendResponseHistory.dropFirst(sentBefore).compactMap { $0 as? GameNetworkModel }
        #expect(replayed.map(\.type) == [.store, .update], "\(replayed.map { "\($0.type)/\($0.subType)" })")
        #expect(replayed.first?.data.data != nil)
        #expect(replayed.last?.subType == .tableWeather)

        // The late player draws it straight away.
        for message in replayed {
            _ = try await env.player2.handleWeather(message)
        }
        #expect(env.player2.gameModel.tableWeather.visibleWeatherId == fixture.weatherId)
    }

    // MARK: - Fixture

    private struct Fixture {
        let environment: MultiConnectionTestEnvironment
        let weatherId: UUID
    }

    private static func fixture() async throws -> Fixture {
        let environment = try await MultiConnectionTestEnvironment.create()
        let photoId = await environment.masterRoot.photoRoot.itemController.addNew(type: .entry)
        environment.masterRoot.photoRoot.editController.reset(name: "Storm backdrop", itemId: photoId)
        let weatherId = await environment.masterRoot.weatherRoot.itemController.addNew(type: .scenario)
        environment.masterRoot.weatherRoot.editController.reset(name: "Storm front", itemId: weatherId)
        environment.masterRoot.weatherRoot.editController.add(photoId: photoId, itemId: weatherId)
        environment.masterRoot.adventureRoot.startGame()
        environment.player1Root.adventureRoot.startGame()
        environment.player2Root.adventureRoot.startGame()
        return Fixture(environment: environment, weatherId: weatherId)
    }

    private static func lastTableWeather(in environment: MultiConnectionTestEnvironment) -> GameNetworkModel? {
        environment.masterNetworkSpy.sendResponseHistory
            .compactMap { $0 as? GameNetworkModel }
            .last { $0.type == .update && $0.subType == .tableWeather }
    }
}
#endif
