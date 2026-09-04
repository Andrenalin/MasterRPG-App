// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PdfRPG

@MainActor
struct GameControllerTests {
    @Test("PDF list reports locally available database versions")
    func pdfListReportsLocalVersions() async throws {
        // Given
        let root = try await Self.setupPdf()
        let sut = root.gameController
        let masterId = UUID()
        let pdfId = try #require(root.itemController.itemDataModel.items.first)
        let expectedVersion = await sut.networkVersion(for: pdfId)

        // When
        let data = await sut.pdfList(allPlayers: false, with: masterId)
        let request = try #require(PdfListRequest.decodeData(of: data.data))

        // Then
        #expect(data.type == .pdf)
        #expect(data.version == 0)
        #expect(request.list == [pdfId: expectedVersion])
        #expect(request.players.isEmpty)
    }

    @Test("PDF availability accepts matching versions and retains mismatching reports")
    func pdfAvailabilityUsesMasterVersion() async throws {
        // Given
        let root = try await Self.setupPdf()
        let sut = root.gameController
        let masterId = UUID()
        let matchingPlayerId = UUID()
        let mismatchingPlayerId = UUID()
        let localData = await sut.pdfList(allPlayers: false, with: masterId)
        let localRequest = try #require(PdfListRequest.decodeData(of: localData.data))
        let (pdfId, masterVersion) = try #require(localRequest.list.first)

        // When
        let appliedMatching = await sut.applyPdfList(
            data: Self.pdfListData(PdfListRequest(list: [pdfId: masterVersion], players: [:])),
            for: matchingPlayerId,
            with: masterId,
            authoritative: false
        )
        let appliedMismatching = await sut.applyPdfList(
            data: Self.pdfListData(PdfListRequest(list: [pdfId: masterVersion + 1], players: [:])),
            for: mismatchingPlayerId,
            with: masterId,
            authoritative: false
        )

        // Then
        #expect(appliedMatching)
        #expect(appliedMismatching)
        #expect(sut.masterVersion(for: pdfId, masterId: masterId) == masterVersion)
        #expect(sut.reportedVersion(for: pdfId, playerId: mismatchingPlayerId) == masterVersion + 1)
        #expect(sut.isPdfAvailable(itemId: pdfId, for: masterId, masterId: masterId))
        #expect(sut.isPdfAvailable(itemId: pdfId, for: matchingPlayerId, masterId: masterId))
        #expect(!sut.isPdfAvailable(itemId: pdfId, for: mismatchingPlayerId, masterId: masterId))
        #expect(Set(sut.gameModel.playerReport(for: pdfId)) == [masterId, matchingPlayerId])
    }

    @Test("Authoritative PDF matrix uses the master's list as its baseline")
    func authoritativePdfListUsesMasterListAsBaseline() async {
        // Given
        let root = PdfRootModel.testRoot()
        let sut = root.gameController
        let pdfId = UUID()
        let masterId = UUID()
        let matchingPlayerId = UUID()
        let mismatchingPlayerId = UUID()
        let masterVersion = 7
        let request = PdfListRequest(
            list: [pdfId: masterVersion],
            players: [
                pdfId: [
                    masterId: masterVersion + 10,
                    matchingPlayerId: masterVersion,
                    mismatchingPlayerId: masterVersion - 1
                ]
            ]
        )

        // When
        let applied = await sut.applyPdfList(
            data: Self.pdfListData(request),
            for: masterId,
            with: masterId,
            authoritative: true
        )

        // Then
        #expect(applied)
        #expect(sut.masterVersion(for: pdfId, masterId: masterId) == masterVersion)
        #expect(sut.isPdfAvailable(itemId: pdfId, for: masterId, masterId: masterId))
        #expect(sut.isPdfAvailable(itemId: pdfId, for: matchingPlayerId, masterId: masterId))
        #expect(!sut.isPdfAvailable(itemId: pdfId, for: mismatchingPlayerId, masterId: masterId))
        #expect(Set(sut.gameModel.playerReport(for: pdfId)) == [masterId, matchingPlayerId])
    }

    @Test("Malformed and missing PDF lists leave availability unchanged")
    func malformedPdfListsAreIgnored() async {
        // Given
        let sut = PdfRootModel.testRoot().gameController
        let pdfId = UUID()
        let masterId = UUID()
        let playerId = UUID()
        sut.setMasterVersion(itemId: pdfId, version: 6, masterId: masterId)
        sut.markPdfAvailable(itemId: pdfId, version: 6, for: [playerId], masterId: masterId)
        let originalVersions = sut.versionLedger.playerVersions
        let originalReports = sut.gameModel.playerReports
        let malformedData = NetworkCodableDataType(
            id: UUID(),
            type: .pdf,
            version: 0,
            data: Data("not a PDF list".utf8)
        )
        let missingData = NetworkCodableDataType(
            id: UUID(),
            type: .pdf,
            version: 0,
            data: nil
        )

        // When
        let appliedMalformed = await sut.applyPdfList(
            data: malformedData,
            for: playerId,
            with: masterId,
            authoritative: true
        )
        let appliedMissing = await sut.applyPdfList(
            data: missingData,
            for: playerId,
            with: masterId,
            authoritative: false
        )

        // Then
        #expect(!appliedMalformed)
        #expect(!appliedMissing)
        #expect(sut.versionLedger.playerVersions == originalVersions)
        #expect(sut.gameModel.playerReports == originalReports)
        #expect(sut.isPdfAvailable(itemId: pdfId, for: playerId, masterId: masterId))
    }

    @Test("Removing a player removes every PDF version report")
    func removePdfReportsRemovesPlayerFromEveryPdf() {
        // Given
        let sut = PdfRootModel.testRoot().gameController
        let firstPdfId = UUID()
        let secondPdfId = UUID()
        let masterId = UUID()
        let lostPlayerId = UUID()
        let connectedPlayerId = UUID()
        sut.setMasterVersion(itemId: firstPdfId, version: 4, masterId: masterId)
        sut.setMasterVersion(itemId: secondPdfId, version: 9, masterId: masterId)
        sut.markPdfAvailable(
            itemId: firstPdfId,
            version: 4,
            for: [lostPlayerId, connectedPlayerId],
            masterId: masterId
        )
        sut.markPdfAvailable(
            itemId: secondPdfId,
            version: 9,
            for: [lostPlayerId, connectedPlayerId],
            masterId: masterId
        )

        // When
        sut.removePdfReports(for: lostPlayerId)

        // Then
        #expect(sut.reportedVersion(for: firstPdfId, playerId: lostPlayerId) == nil)
        #expect(sut.reportedVersion(for: secondPdfId, playerId: lostPlayerId) == nil)
        #expect(!sut.gameModel.playerReport(for: firstPdfId).contains(lostPlayerId))
        #expect(!sut.gameModel.playerReport(for: secondPdfId).contains(lostPlayerId))
        #expect(sut.isPdfAvailable(itemId: firstPdfId, for: connectedPlayerId, masterId: masterId))
        #expect(sut.isPdfAvailable(itemId: secondPdfId, for: connectedPlayerId, masterId: masterId))
    }

    @Test("Reset clears PDF availability and generic player reports")
    func resetClearsPdfReports() async {
        // Given
        let sut = PdfRootModel.testRoot().gameController
        let pdfId = UUID()
        let masterId = UUID()
        let playerId = UUID()
        sut.setMasterVersion(itemId: pdfId, version: 12, masterId: masterId)
        sut.markPdfAvailable(itemId: pdfId, version: 12, for: [playerId], masterId: masterId)

        // When
        await sut.reset()

        // Then
        #expect(sut.versionLedger.playerVersions.isEmpty)
        #expect(sut.gameModel.playerReports.isEmpty)
        #expect(sut.masterVersion(for: pdfId, masterId: masterId) == nil)
        #expect(!sut.isPdfAvailable(itemId: pdfId, for: playerId, masterId: masterId))
    }
}

private extension GameControllerTests {
    static func setupPdf() async throws -> PdfRootModel {
        let root = PdfRootModel.testRoot()
        await root.itemController.resetData()
        await root.gameController.reset()

        let url = try #require(
            ResourcesDebug.bundle.url(
                forResource: ResourcesDebug.pdfTestData,
                withExtension: "gmz"
            )
        )
        let task = root.importController.importUrl(from: url)
        _ = try await task.value

        #expect(root.itemController.itemDataModel.items.count == 1)
        return root
    }

    static func pdfListData(_ request: PdfListRequest) -> NetworkCodableDataType {
        NetworkCodableDataType(
            id: UUID(),
            type: .pdf,
            version: 0,
            data: request.encodeData()
        )
    }
}
