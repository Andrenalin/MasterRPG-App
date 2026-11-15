// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import GameRPG
@testable import WeatherRPG

/// The game master's tap on a weather's lightning is sent to the players, who draw the same bolt.
@Suite("Weather lightning", .serialized)
@MainActor
struct WeatherLightningTests {
    // MARK: - Payload

    @Test("The payload round-trips, is range-checked and is no asset or presentation")
    func payloadAndShape() throws {
        let strike = WeatherLightningStrike(weatherId: UUID(), startFraction: 0.25, seed: 42)
        let data = strike.networkData
        #expect(data.id == strike.weatherId)
        #expect(data.type == .weather)
        #expect(WeatherLightningStrike.decodeData(of: data.data) == strike)
        #expect(strike.isValid)
        #expect(!WeatherLightningStrike(weatherId: UUID(), startFraction: 1.5, seed: 1).isValid)
        #expect(!WeatherLightningStrike(weatherId: UUID(), startFraction: .nan, seed: 1).isValid)

        let message = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
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

    @Test("A bolt with the same spec grows the same way")
    func boltIsDeterministic() {
        let spec = LightningBoltSpec(startFraction: 0.3, seed: 7)
        func points() -> [CGPoint] {
            let lightning = Lightning(maximumBolts: 4, forkProbability: 20)
            lightning.strike(spec)
            let size = CGSize(width: 400, height: 800)
            var date = Date(timeIntervalSince1970: 1_000)
            lightning.lastUpdate = date
            for _ in 0 ..< 40 {
                date += 1.0 / 60
                lightning.update(date: date, in: size)
            }
            return lightning.bolts.flatMap(\.points)
        }
        let first = points()
        #expect(!first.isEmpty)
        #expect(first == points())
        // It starts where the spec says: 50 pt in from the edges, 30 % across the rest.
        #expect(first.first?.x == 50 + 0.3 * 300)
    }

    @Test("A running strike is not restarted")
    func strikeIsNotRestarted() {
        let lightning = Lightning(maximumBolts: 4, forkProbability: 20)
        #expect(lightning.strike())
        #expect(!lightning.strike())
    }

    // MARK: - Message flow

    @Test("The game master's strike reaches a player; a player's or a stale one does not")
    func flow() async throws {
        let env = try await MultiConnectionTestEnvironment.create()
        let weatherId = await env.masterRoot.weatherRoot.itemController.addNew(type: .scenario)
        env.masterRoot.adventureRoot.startGame()
        env.player1Root.adventureRoot.startGame()

        let strike = WeatherLightningStrike(weatherId: weatherId, startFraction: 0.6, seed: 99)

        // Another weather is on screen: nothing is sent.
        let before = env.masterNetworkSpy.sendResponseHistory.count
        await env.master.game(message: strike.networkData, actionType: .generic)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == before)

        // The weather is on screen: every player gets the strike as a plain update.
        let isCurrent = await env.masterRoot.weatherRoot.gameControllable.setCurrent(itemId: weatherId)
        #expect(isCurrent)
        await env.master.game(message: strike.networkData, actionType: .generic)
        let sent = env.masterNetworkSpy.sendResponseHistory.dropFirst(before).compactMap { $0 as? GameNetworkModel }
        let message = try #require(sent.last)
        #expect(message.type == .update)
        #expect(message.subType == .generic)
        #expect(message.sender.isMaster)
        #expect(!message.carriesAsset)

        // A damaged payload is not sent.
        let damaged = WeatherLightningStrike(weatherId: weatherId, startFraction: 4, seed: 1)
        let countBefore = env.masterNetworkSpy.sendResponseHistory.count
        await env.master.game(message: damaged.networkData, actionType: .generic)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == countBefore)

        // The player hands it to its weather viewers and answers nothing.
        let player = env.player1Root.weatherRoot
        #expect(player.receivedLightning == nil)
        let answer = try await env.player1.handleWeather(message)
        #expect(answer == nil)
        #expect(player.receivedLightning?.strike == strike)

        // A strike from a player is ignored.
        let other = WeatherLightningStrike(weatherId: weatherId, startFraction: 0.1, seed: 5)
        let forged = env.player2Root.gameModel.outgoingMessage(
            counter: 99,
            type: .update,
            subType: .generic,
            asMaster: false,
            data: other.networkData
        )
        _ = try await env.player1.handleWeather(forged)
        #expect(player.receivedLightning?.strike == strike)

        // A player's own `game` call for a weather publishes nothing.
        let playerCountBefore = env.playerNetworkSpy.calledRequest
        await env.player1.game(message: other.networkData, actionType: .generic)
        #expect(env.playerNetworkSpy.calledRequest == playerCountBefore)
    }
}
#endif
