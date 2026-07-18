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
    @Test("First Weather show is full over Journal and a same-version reshow is reference-only")
    func firstShowIsFullAndReshowIsReferenceOnly() async throws {
        // Given
        let fixture = try await Self.preparedFixture()
        let reference = await fixture.environment.masterRoot.weatherRoot.weatherGameControllable.shareWeather(
            id: fixture.weatherId
        )

        // When - The master presents this Weather version for the first time.
        await fixture.environment.master.show(for: reference)

        // Then - Weather and its optional Photo travel together through Journal.
        let initialShow = try #require(
            fixture.environment.masterNetworkSpy.sendResponseData as? GameNetworkModel
        )
        #expect(initialShow.type == .reveal)
        #expect(initialShow.subType == .show)
        #expect(initialShow.data.id == fixture.weatherId)
        #expect(initialShow.data.version == reference.version)
        #expect(initialShow.data.data != nil)
        #expect(initialShow.usesFileJournal)
        #expect(RPGSharePlayController.usesJournalTransport(
            for: initialShow,
            fileJournal: initialShow.usesFileJournal,
            journalAvailable: true
        ))

        let acknowledgement = try #require(
            try await fixture.environment.player1.handleWeather(initialShow)
        )
        #expect(acknowledgement.subType == .ok)
        #expect(acknowledgement.data.version == reference.version)
        #expect(
            await fixture.environment.player1Root.weatherRoot.gameControllable.currentId
                == fixture.weatherId
        )

        // A received game Weather and its linked Photo stay in game memory.
        #expect(fixture.environment.player1Root.weatherRoot.itemController.itemDataModel.items.isEmpty)
        #expect(fixture.environment.player1Root.photoRoot.itemController.itemDataModel.items.isEmpty)
        #expect(
            fixture.environment.player1Root.photoRoot.gameControllable.gameModel
                .itemData[fixture.photoId] != nil
        )

        // When - The master presents the exact same Weather/Photo version again.
        await fixture.environment.master.show(for: reference)

        // Then - Only the stable reference is sent; a player that still has it
        // can acknowledge without another package transfer.
        let reshow = try #require(
            fixture.environment.masterNetworkSpy.sendResponseData as? GameNetworkModel
        )
        #expect(reshow.type == .reveal)
        #expect(reshow.subType == .show)
        #expect(reshow.data.id == fixture.weatherId)
        #expect(reshow.data.version == reference.version)
        #expect(reshow.data.data == nil)
        #expect(!reshow.usesFileJournal)

        let reshowAcknowledgement = try #require(
            try await fixture.environment.player1.handleWeather(reshow)
        )
        #expect(reshowAcknowledgement.subType == .ok)
        #expect(reshowAcknowledgement.data.data == nil)
    }

    @Test("A player missing a referenced Weather requests and receives the canonical full package")
    func missingReferenceRequestsCanonicalJournalRepair() async throws {
        // Given - Player 1 receives the first broadcast, while player 2 joins
        // later and sees only the same-version reshow reference.
        let fixture = try await Self.preparedFixture()
        let reference = await fixture.environment.masterRoot.weatherRoot.weatherGameControllable.shareWeather(
            id: fixture.weatherId
        )
        await fixture.environment.master.show(for: reference)
        await fixture.environment.master.show(for: reference)
        let reshow = try #require(
            fixture.environment.masterNetworkSpy.sendResponseData as? GameNetworkModel
        )
        #expect(reshow.data.data == nil)

        // When - The missing player handles the reference.
        let request = try #require(
            try await fixture.environment.player2.handleWeather(reshow)
        )

        // Then - It asks the master for this exact version without uploading data.
        #expect(request.type == .reveal)
        #expect(request.subType == .show)
        #expect(request.data.id == fixture.weatherId)
        #expect(request.data.version == reference.version)
        #expect(request.data.data == nil)

        // When - The master answers the request from its canonical store.
        let canonical = try #require(
            try await fixture.environment.master.handleWeather(request)
        )
        let repair = fixture.environment.masterRoot.gameModel.outgoingMessage(
            counter: 101,
            type: request.type,
            subType: request.subType,
            asMaster: true,
            targetId: fixture.environment.player2Config.id,
            data: canonical
        )

        // Then - Every full repair is Journal-eligible and retains the target.
        #expect(canonical.id == fixture.weatherId)
        #expect(canonical.version == reference.version)
        #expect(canonical.data != nil)
        #expect(repair.targetId == fixture.environment.player2Config.id)
        #expect(repair.usesFileJournal)
        #expect(RPGSharePlayController.usesJournalTransport(
            for: repair,
            fileJournal: repair.usesFileJournal,
            journalAvailable: true
        ))

        let acknowledgement = try #require(
            try await fixture.environment.player2.handleWeather(repair)
        )
        #expect(acknowledgement.subType == .ok)
        #expect(
            await fixture.environment.player2Root.weatherRoot.gameControllable.currentId
                == fixture.weatherId
        )
        #expect(fixture.environment.player2Root.weatherRoot.itemController.itemDataModel.items.isEmpty)
        #expect(fixture.environment.player2Root.photoRoot.itemController.itemDataModel.items.isEmpty)
        #expect(
            fixture.environment.player2Root.photoRoot.gameControllable.gameModel
                .itemData[fixture.photoId] != nil
        )
    }

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
        let acknowledgement = try #require(
            try await fixture.environment.player1.handleWeather(initialShow)
        )
        let connectionId = ConnectionController.ID()
        fixture.environment.master.gameModel.add(
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
