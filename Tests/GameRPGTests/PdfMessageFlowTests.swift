// @copyright André Trettin

#if canImport(Testing)
import AdventureRPG
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import GameRPG
@testable import PdfRPG

@Suite("PDF availability message sequencing", .serialized)
@MainActor
struct PdfMessageFlowTests {
    enum PlayerFileIngress: CaseIterable, Sendable {
        case localNetwork
        case sharePlay
    }

    @Test("PDF asset repair returns canonical bytes without a group rebroadcast")
    func pdfAssetRepairIsRequesterOnly() async throws {
        let env = try await Self.preparedEnvironment()
        let pdfId = try #require(env.masterRoot.pdfRoot.itemController.itemDataModel.items.first)
        let reference = await env.masterRoot.pdfRoot.gameControllable.share(id: pdfId)
        let request = env.player1Root.gameModel.outgoingMessage(
            counter: 4,
            type: .reveal,
            subType: .show,
            asMaster: false,
            data: reference
        )
        let broadcastCount = env.masterNetworkSpy.sendResponseHistory.count

        let repair = try #require(try await env.master.handlePdf(request))

        #expect(repair.id == pdfId)
        #expect(repair.effectiveAssetVersion == reference.effectiveAssetVersion)
        #expect(repair.data != nil)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == broadcastCount)
    }

    @Test("Master ignores stale, duplicate, negative, and malformed PDF lists")
    func masterIgnoresInvalidPdfListSequence() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let pdfId = try #require(env.masterRoot.pdfRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.pdfRoot.gameController.networkVersion(for: pdfId)

        _ = try await env.master.handlePdf(
            Self.pdfReport(from: env.player1Root, versions: [pdfId: version], counter: 5)
        )
        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        #expect(env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // When
        _ = try await env.master.handlePdf(
            Self.pdfReport(from: env.player1Root, versions: [:], counter: 4)
        )
        _ = try await env.master.handlePdf(
            Self.pdfReport(from: env.player1Root, versions: [:], counter: 5)
        )
        _ = try await env.master.handlePdf(
            Self.pdfReport(from: env.player1Root, versions: [:], counter: -1)
        )
        _ = try await env.master.handlePdf(
            Self.malformedPdfReport(from: env.player1Root, counter: 10)
        )

        // Then
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline)
        #expect(env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // Decoding failed before sequence state was recorded, so counter 6 is
        // still newer than the last valid packet and replaces the report.
        _ = try await env.master.handlePdf(
            Self.pdfReport(from: env.player1Root, versions: [:], counter: 6)
        )
        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
        #expect(!env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("Player ignores stale authoritative PDF lists and malformed packets do not advance sequence")
    func playerIgnoresInvalidAuthoritativePdfListSequence() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let pdfId = UUID()
        let version = 27
        let players = [
            pdfId: [
                env.masterConfig.id: version,
                env.player1Config.id: version
            ]
        ]

        _ = try await env.player1.handlePdf(
            Self.authoritativePdfList(
                from: env.masterRoot,
                counter: 5,
                list: [pdfId: version],
                players: players
            )
        )

        // When
        _ = try await env.player1.handlePdf(
            Self.authoritativePdfList(from: env.masterRoot, counter: 4, list: [:], players: [:])
        )
        _ = try await env.player1.handlePdf(
            Self.authoritativePdfList(from: env.masterRoot, counter: 5, list: [:], players: [:])
        )
        _ = try await env.player1.handlePdf(
            Self.authoritativePdfList(from: env.masterRoot, counter: -1, list: [:], players: [:])
        )
        _ = try await env.player1.handlePdf(
            Self.malformedAuthoritativePdfList(from: env.masterRoot, counter: 10)
        )

        // Then
        #expect(env.player1Root.pdfRoot.pdfGameControllable.masterVersion(
            for: pdfId,
            masterId: env.masterConfig.id
        ) == version)
        #expect(env.player1Root.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // The malformed counter was not recorded, so a later valid counter 6
        // can replace the authoritative snapshot.
        _ = try await env.player1.handlePdf(
            Self.authoritativePdfList(from: env.masterRoot, counter: 6, list: [:], players: [:])
        )
        #expect(env.player1Root.pdfRoot.pdfGameControllable.masterVersion(
            for: pdfId,
            masterId: env.masterConfig.id
        ) == nil)
    }

    @Test("Lost player is removed from PDF reports and may report again from a reset counter")
    func lostPlayerClearsPdfAvailabilityAndSequence() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let pdfId = try #require(env.masterRoot.pdfRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.pdfRoot.gameController.networkVersion(for: pdfId)
        let connectionId = ConnectionController.ID()
        let report = Self.pdfReport(
            from: env.player1Root,
            versions: [pdfId: version],
            counter: 8
        )

        await env.master.receivedProcess(report, connectionId: connectionId)
        #expect(env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))

        // When
        await env.master.lostPlayer(for: connectionId)

        // Then
        #expect(!env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
        #expect(env.masterRoot.pdfRoot.pdfGameControllable.reportedVersion(
            for: pdfId,
            playerId: env.player1Config.id
        ) == nil)
        #expect(!env.masterRoot.pdfRoot.gameController.gameModel.playerReport(for: pdfId).contains(env.player1Config.id))

        let baseline = env.masterNetworkSpy.sendResponseHistory.count
        _ = try await env.master.handlePdf(
            Self.pdfReport(from: env.player1Root, versions: [pdfId: version], counter: 1)
        )

        #expect(env.masterNetworkSpy.sendResponseHistory.count == baseline + 1)
        #expect(env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
    }

    @Test("PDF list updates are not presentation intents")
    func pdfListIsNotPresentationIntent() async throws {
        // Given
        let env = try await MultiConnectionTestEnvironment.create()
        let model = Self.authoritativePdfList(
            from: env.masterRoot,
            counter: 5,
            list: [UUID(): 7],
            players: [:]
        )

        // Then
        #expect(model.sender.isMaster)
        #expect(model.type == .update)
        #expect(model.subType == .pdfList)
        #expect(!model.isPresentation)
    }

    @Test("Master and player ignore failed PDF messages")
    func failedPdfMessagesAreIgnored() async throws {
        // Given
        let env = try await Self.preparedEnvironment()
        let pdfId = try #require(env.masterRoot.pdfRoot.itemController.itemDataModel.items.first)
        let version = await env.masterRoot.pdfRoot.gameController.networkVersion(for: pdfId)
        let playerFailure = env.player1Root.gameModel.outgoingMessage(
            counter: 3,
            type: .reveal,
            subType: .failed,
            asMaster: false,
            data: NetworkCodableDataType(id: pdfId, type: .pdf, version: version)
        )
        let masterFailure = env.masterRoot.gameModel.outgoingMessage(
            counter: 4,
            type: .reveal,
            subType: .failed,
            asMaster: true,
            data: NetworkCodableDataType(id: pdfId, type: .pdf, version: version)
        )
        let masterSendCount = env.masterNetworkSpy.sendResponseHistory.count
        let playerRequestCount = env.playerNetworkSpy.calledRequest

        // When
        let masterResult = try await env.master.handlePdf(playerFailure)
        let playerResult = try await env.player1.handlePdf(masterFailure)

        // Then
        #expect(masterResult == nil)
        #expect(playerResult == nil)
        #expect(env.masterNetworkSpy.sendResponseHistory.count == masterSendCount)
        #expect(env.playerNetworkSpy.calledRequest == playerRequestCount)
        #expect(!env.masterRoot.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: pdfId,
            for: env.player1Config.id,
            masterId: env.masterConfig.id
        ))
        #expect(await env.player1Root.pdfRoot.gameControllable.currentId != pdfId)
    }

}

private extension PdfMessageFlowTests {
    static func preparedEnvironment() async throws -> MultiConnectionTestEnvironment {
        let env = try await MultiConnectionTestEnvironment.create()
        try await MockRoot.importTestData(
            into: env.masterRoot.adventureRoot,
            name: ResourcesDebug.pdfTestData,
            itemCounter: 0
        )
        env.masterRoot.adventureRoot.startGame()
        return env
    }

    static func pdfReport(
        from root: GameRoot,
        versions: [UUID: Int],
        counter: Int
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .pdfList,
            asMaster: false,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .pdf,
                version: 0,
                data: PdfListRequest(list: versions, players: [:]).encodeData()
            )
        )
    }

    static func malformedPdfReport(from root: GameRoot, counter: Int) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .pdfList,
            asMaster: false,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .pdf,
                version: 0,
                data: Data([0xFF])
            )
        )
    }

    static func authoritativePdfList(
        from root: GameRoot,
        counter: Int,
        list: [UUID: Int],
        players: [UUID: [UUID: Int]]
    ) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .pdfList,
            asMaster: true,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .pdf,
                version: 0,
                data: PdfListRequest(list: list, players: players).encodeData()
            )
        )
    }

    static func malformedAuthoritativePdfList(from root: GameRoot, counter: Int) -> GameNetworkModel {
        root.gameModel.outgoingMessage(
            counter: counter,
            type: .update,
            subType: .pdfList,
            asMaster: true,
            data: NetworkCodableDataType(
                id: UUID(),
                type: .pdf,
                version: 0,
                data: Data([0xFF])
            )
        )
    }

    static func playerPdfReveal(
        from player: GameConfigModel,
        masterId: UUID,
        counter: Int,
        data: NetworkCodableDataType
    ) -> GameNetworkModel {
        GameNetworkModel(
            counter: counter,
            proxyCounter: 0,
            type: .reveal,
            subType: .show,
            masterId: masterId,
            sender: GameSenderModel(
                id: player.id,
                role: .player,
                name: "PDF Player",
                characterId: nil
            ),
            data: data
        )
    }
}
#endif
