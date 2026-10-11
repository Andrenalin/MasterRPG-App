// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import GameRPG
@testable import PhotoRPG
@testable import WeatherRPG

@Suite("Weather journal message flow", .serialized)
@MainActor
struct WeatherMessageFlowTests {

    @Test("Master validates a Weather receipt and removes it when that player is lost")
    func acknowledgementAndLostPlayerMaintainReports() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let reference = await fixture.environment.masterRoot.weatherRoot.weatherGameControllable.shareWeather(
            id: fixture.weatherId
        )
        await fixture.environment.master.show(for: reference)
        let initialShow = try #require(
            fixture.environment.masterNetworkSpy.sendResponseData as? GameNetworkModel
        )
        // The show names the Weather; the player lacks it, asks, and acknowledges the package.
        let request = try #require(
            try await fixture.environment.player1.handleWeather(initialShow)
        )
        #expect(request.isAssetRequest)
        var delivery = initialShow
        delivery.data = try #require(try await fixture.environment.master.handleWeather(request))
        let acknowledgement = try #require(
            try await fixture.environment.player1.handleWeather(delivery)
        )
        #expect(acknowledgement.subType == .ok)
        let connectionId = ConnectionController.ID()
        fixture.environment.master.bind(
            connectionId: connectionId,
            playerId: fixture.environment.player1Config.id
        )

        // Failed and stale-version receipts must not grant availability.
        var failedReceipt = acknowledgement
        failedReceipt.subType = .failed
        #expect(try await fixture.environment.master.handleWeather(failedReceipt) == nil)
        #expect(
            fixture.environment.masterRoot.weatherRoot.gameControllable.gameModel
                .playerReport(for: fixture.weatherId)
                .isEmpty
        )

        var staleReceipt = acknowledgement
        staleReceipt.data = NetworkCodableDataType(
            id: acknowledgement.data.id,
            type: .weather,
            version: acknowledgement.data.version + 1
        )
        #expect(try await fixture.environment.master.handleWeather(staleReceipt) == nil)
        #expect(
            fixture.environment.masterRoot.weatherRoot.gameControllable.gameModel
                .playerReport(for: fixture.weatherId)
                .isEmpty
        )

        // When - The exact package version is acknowledged.
        let response = try await fixture.environment.master.handleWeather(acknowledgement)

        // Then
        #expect(response == nil)
        #expect(
            fixture.environment.masterRoot.weatherRoot.gameControllable.gameModel
                .playerReport(for: fixture.weatherId)
                .contains(fixture.environment.player1Config.id)
        )

        // When - That connection is lost.
        await fixture.environment.master.lostPlayer(for: connectionId)

        // Then - A reconnect must prove possession again.
        #expect(
            !fixture.environment.masterRoot.weatherRoot.gameControllable.gameModel
                .playerReport(for: fixture.weatherId)
                .contains(fixture.environment.player1Config.id)
        )
    }

    @Test(
        "Player ignores Weather acknowledgements and failures",
        arguments: [RPGMessageActionType.ok, .failed]
    )
    func playerIgnoresWeatherReceiptMessages(_ receipt: RPGMessageActionType) async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let reference = await fixture.environment.masterRoot.weatherRoot.weatherGameControllable.shareWeather(
            id: fixture.weatherId
        )
        let message = fixture.environment.masterRoot.gameModel.outgoingMessage(
            counter: 7,
            type: .reveal,
            subType: receipt,
            asMaster: true,
            data: reference
        )

        // When
        let response = try await fixture.environment.player1.handleWeather(message)

        // Then
        #expect(response == nil)
        #expect(fixture.environment.player1.gameModel.gameUpdateType == .none)
        #expect(
            await fixture.environment.player1Root.weatherRoot.gameControllable.currentId
                != fixture.weatherId
        )
        #expect(fixture.environment.player1Root.weatherRoot.itemController.itemDataModel.items.isEmpty)
    }

    @Test("Player readiness sends no Weather list")
    func readySendsNoWeatherList() async throws {
        // Given
        let environment = try await MultiConnectionTestEnvironment.create()

        // When
        await environment.player1.readyProxy()

        // Then - Weather is session-only, so connection setup reports only the
        // four modules that can already exist in player persistence.
        let reports = environment.playerNetworkSpy.requestHistory.compactMap {
            $0 as? GameNetworkModel
        }
        #expect(!reports.contains { $0.data.type == .weather })
        #expect(Set(reports.map(\.subType)) == [
            .audioList,
            .photoList,
            .pdfList,
            .spaceList
        ])
    }
}

private extension WeatherMessageFlowTests {
    struct Fixture {
        let environment: MultiConnectionTestEnvironment
        let weatherId: UUID
        let photoId: UUID
    }

    static func preparedFixture() async throws -> Fixture {
        let environment = try await MultiConnectionTestEnvironment.create()

        let photoId = await environment.masterRoot.photoRoot.itemController.addNew(type: .entry)
        environment.masterRoot.photoRoot.editController.reset(
            name: "Storm backdrop",
            itemId: photoId
        )

        let weatherId = await environment.masterRoot.weatherRoot.itemController.addNew(type: .scenario)
        environment.masterRoot.weatherRoot.editController.reset(
            name: "Storm front",
            itemId: weatherId
        )
        environment.masterRoot.weatherRoot.editController.add(
            photoId: photoId,
            itemId: weatherId
        )

        environment.masterRoot.adventureRoot.startGame()
        environment.player1Root.adventureRoot.startGame()
        environment.player2Root.adventureRoot.startGame()

        return Fixture(environment: environment, weatherId: weatherId, photoId: photoId)
    }
}
#endif
