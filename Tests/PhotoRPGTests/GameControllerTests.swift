// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PhotoRPG

@MainActor
struct GameControllerTests {
    @Test func photoListRequestRoundTrips() throws {
        let firstPhotoId = UUID()
        let secondPhotoId = UUID()
        let masterId = UUID()
        let playerId = UUID()
        let request = PhotoListRequest(
            list: [firstPhotoId: 3, secondPhotoId: 8],
            players: [
                firstPhotoId: [masterId: 3, playerId: 3],
                secondPhotoId: [masterId: 8, playerId: 7]
            ]
        )

        let encoded = try #require(request.encodeData())

        #expect(PhotoListRequest.decodeData(of: encoded) == request)
    }

    @Test func playerPhotoListUsesLocalMasterVersionForAvailability() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController
        let masterId = UUID()
        let matchingPlayerId = UUID()
        let mismatchingPlayerId = UUID()

        // Point one item at a dedicated temp file with its own fresh fileId instead of
        // the shared fixture's file/bookmark — other tests reset that fixture (removing
        // its bookmarks) while this one awaits, which made the local availability check
        // below intermittently report no local data and drop the master's version.
        let photoId = try #require(root.itemController.itemDataModel.items.first)
        let tempUrl = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).dat")
        try Data("local-master-version-content".utf8).write(to: tempUrl)
        defer { try? FileManager.default.removeItem(at: tempUrl) }
        root.itemController.itemOrEmpty(for: photoId).fileUrl = FileUrl(
            fileId: UUID(), url: tempUrl, location: .other, module: "photo", relativeUrl: nil
        )

        let localData = await sut.photoList(allPlayers: false, with: masterId)
        let localRequest = try #require(PhotoListRequest.decodeData(of: localData.data))
        let masterVersion = try #require(localRequest.list[photoId])

        let matchingRequest = PhotoListRequest(list: [photoId: masterVersion], players: [:])
        let matchingData = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: 0,
            data: matchingRequest.encodeData()
        )
        let appliedMatching = await sut.applyPhotoList(
            data: matchingData,
            for: matchingPlayerId,
            with: masterId,
            authoritative: false
        )

        let mismatchingRequest = PhotoListRequest(list: [photoId: masterVersion + 1], players: [:])
        let mismatchingData = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: 0,
            data: mismatchingRequest.encodeData()
        )
        let appliedMismatching = await sut.applyPhotoList(
            data: mismatchingData,
            for: mismatchingPlayerId,
            with: masterId,
            authoritative: false
        )

        #expect(appliedMatching)
        #expect(appliedMismatching)
        #expect(sut.masterVersion(for: photoId, masterId: masterId) == masterVersion)
        #expect(sut.isPhotoAvailable(itemId: photoId, for: masterId, masterId: masterId))
        #expect(sut.isPhotoAvailable(itemId: photoId, for: matchingPlayerId, masterId: masterId))
        #expect(!sut.isPhotoAvailable(itemId: photoId, for: mismatchingPlayerId, masterId: masterId))
    }

    @Test func authoritativePhotoListUsesMasterListAsBaseline() async {
        let sut = PhotoRootModel.testRoot().gameController
        let photoId = UUID()
        let masterId = UUID()
        let matchingPlayerId = UUID()
        let mismatchingPlayerId = UUID()
        let masterVersion = 7
        let request = PhotoListRequest(
            list: [photoId: masterVersion],
            players: [
                photoId: [
                    masterId: masterVersion + 10,
                    matchingPlayerId: masterVersion,
                    mismatchingPlayerId: masterVersion - 1
                ]
            ]
        )
        let data = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: 0,
            data: request.encodeData()
        )

        let applied = await sut.applyPhotoList(
            data: data,
            for: masterId,
            with: masterId,
            authoritative: true
        )

        #expect(applied)
        #expect(sut.masterVersion(for: photoId, masterId: masterId) == masterVersion)
        #expect(sut.isPhotoAvailable(itemId: photoId, for: masterId, masterId: masterId))
        #expect(sut.isPhotoAvailable(itemId: photoId, for: matchingPlayerId, masterId: masterId))
        #expect(!sut.isPhotoAvailable(itemId: photoId, for: mismatchingPlayerId, masterId: masterId))
        #expect(Set(sut.gameModel.playerReport(for: photoId)) == [masterId, matchingPlayerId])
    }

    @Test func authoritativePhotoListReplacesPriorReports() async {
        let sut = PhotoRootModel.testRoot().gameController
        let oldPhotoId = UUID()
        let currentPhotoId = UUID()
        let masterId = UUID()
        let oldPlayerId = UUID()
        let currentPlayerId = UUID()
        sut.setMasterVersion(itemId: oldPhotoId, version: 2, masterId: masterId)
        sut.markPhotoAvailable(
            itemId: oldPhotoId,
            version: 2,
            for: [oldPlayerId],
            masterId: masterId
        )
        let request = PhotoListRequest(
            list: [currentPhotoId: 5],
            players: [currentPhotoId: [currentPlayerId: 5]]
        )
        let data = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: 0,
            data: request.encodeData()
        )

        let applied = await sut.applyPhotoList(
            data: data,
            for: masterId,
            with: masterId,
            authoritative: true
        )

        #expect(applied)
        #expect(sut.masterVersion(for: oldPhotoId, masterId: masterId) == nil)
        #expect(sut.gameModel.playerReport(for: oldPhotoId).isEmpty)
        #expect(sut.masterVersion(for: currentPhotoId, masterId: masterId) == 5)
        #expect(sut.isPhotoAvailable(itemId: currentPhotoId, for: currentPlayerId, masterId: masterId))
    }

    @Test func removePhotoReportsRemovesPlayerFromEveryPhoto() {
        let sut = PhotoRootModel.testRoot().gameController
        let firstPhotoId = UUID()
        let secondPhotoId = UUID()
        let masterId = UUID()
        let lostPlayerId = UUID()
        let connectedPlayerId = UUID()
        sut.setMasterVersion(itemId: firstPhotoId, version: 4, masterId: masterId)
        sut.setMasterVersion(itemId: secondPhotoId, version: 9, masterId: masterId)
        sut.markPhotoAvailable(
            itemId: firstPhotoId,
            version: 4,
            for: [lostPlayerId, connectedPlayerId],
            masterId: masterId
        )
        sut.markPhotoAvailable(
            itemId: secondPhotoId,
            version: 9,
            for: [lostPlayerId, connectedPlayerId],
            masterId: masterId
        )

        sut.removePhotoReports(for: lostPlayerId)

        #expect(!sut.isPhotoAvailable(itemId: firstPhotoId, for: lostPlayerId, masterId: masterId))
        #expect(!sut.isPhotoAvailable(itemId: secondPhotoId, for: lostPlayerId, masterId: masterId))
        #expect(sut.isPhotoAvailable(itemId: firstPhotoId, for: connectedPlayerId, masterId: masterId))
        #expect(sut.isPhotoAvailable(itemId: secondPhotoId, for: connectedPlayerId, masterId: masterId))
        #expect(!sut.gameModel.playerReport(for: firstPhotoId).contains(lostPlayerId))
        #expect(!sut.gameModel.playerReport(for: secondPhotoId).contains(lostPlayerId))
    }

    @Test func malformedPhotoListsAreIgnored() async {
        let sut = PhotoRootModel.testRoot().gameController
        let photoId = UUID()
        let masterId = UUID()
        let playerId = UUID()
        sut.setMasterVersion(itemId: photoId, version: 6, masterId: masterId)
        sut.markPhotoAvailable(itemId: photoId, version: 6, for: [playerId], masterId: masterId)
        let originalVersions = sut.versionLedger.playerVersions
        let malformedData = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: 0,
            data: Data("not a photo list".utf8)
        )
        let missingData = NetworkCodableDataType(
            id: UUID(),
            type: .photo,
            version: 0,
            data: nil
        )

        let appliedMalformed = await sut.applyPhotoList(
            data: malformedData,
            for: playerId,
            with: masterId,
            authoritative: true
        )
        let appliedMissing = await sut.applyPhotoList(
            data: missingData,
            for: playerId,
            with: masterId,
            authoritative: false
        )

        #expect(!appliedMalformed)
        #expect(!appliedMissing)
        #expect(sut.versionLedger.playerVersions == originalVersions)
        #expect(sut.isPhotoAvailable(itemId: photoId, for: playerId, masterId: masterId))
    }

    @Test func HasItem() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController

        // random id must be false
        let randomId = UUID()
        var result = await sut.hasItem(id: randomId, version: 0)
        #expect(!result)
        #expect(sut.gameModel.itemData[randomId] == nil)

        let itemId = root.itemController.itemDataModel.items[0]
        let item = root.itemController.itemOrEmpty(for: itemId)
        let version = item.version
        result = await sut.hasItem(id: itemId, version: version + 1)
        #expect(!result)
        #expect(sut.gameModel.itemData[itemId] == nil)

        result = await sut.hasItem(id: root.itemController.itemDataModel.items[0], version: version)
        #expect(result)
        #expect(sut.gameModel.itemData[itemId] != nil)

        result = await sut.hasItem(id: root.itemController.itemDataModel.items[0], version: version + 1)
        #expect(!result)
        #expect(sut.gameModel.itemData[itemId] != nil)
    }
    
    @Test func SetCurrent() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController

        // random id must be false
        let randomId = UUID()
        #expect(await sut.setCurrent(itemId: randomId) == false)
        #expect(await sut.currentId != randomId)

        let itemId = root.itemController.itemDataModel.items[0]
        #expect(await sut.setCurrent(itemId: itemId))
        #expect(await sut.currentId == itemId)
        #expect(sut.gameModel.items[0] == itemId)

        let secondId = root.itemController.itemDataModel.items[1]
        #expect(await sut.setCurrent(itemId: secondId))
        #expect(await sut.currentId == secondId)
        #expect(sut.gameModel.items[0] == secondId)
        #expect(sut.gameModel.items[1] == itemId)

        #expect(await sut.setCurrent(itemId: itemId))
        #expect(await sut.currentId == itemId)
        #expect(sut.gameModel.items[0] == itemId)
        #expect(sut.gameModel.items[1] == secondId)

        await sut.reset()
        #expect(sut.gameModel.items.isEmpty)
        #expect(sut.gameModel.itemData.isEmpty)
        #expect(await sut.currentId != itemId)
    }
    
    @Test func Report() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController

        let itemId = root.itemController.itemDataModel.items[0]
        let playerId = UUID()
        sut.report(itemId: itemId, for: playerId)
        #expect(sut.gameModel.playerReport(for: itemId) == [playerId])

        #expect(await sut.setCurrent(itemId: itemId))
        sut.report(itemId: itemId, for: playerId)
        #expect(sut.gameModel.playerReport(for: itemId) == [playerId])
        sut.report(itemId: itemId, for: playerId)
        #expect(sut.gameModel.playerReport(for: itemId).count == 1)
    }
    
    @Test func CreateGameData() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let itemController = root.itemController
        var exportController = ExportController(itemController: itemController)
        exportController.hubControllable = root
        let sut = GameController(itemController: itemController, exportController: exportController)

        root.itemController.itemDataModel.resetGame(start: true)
        let itemId = root.itemController.itemDataModel.items[0]
        let version = root.itemController.itemOrEmpty(for: itemId).version
        let netdata = try await sut.createGameData(for: itemId)
        #expect(netdata.id == itemId)
        #expect(netdata.type == NetworkModules.photo)
        #expect(netdata.version == version)

        await root.itemController.delete(itemId: itemId)
        #expect(root.itemController.itemDataModel.itemData[itemId] == nil)

        let success = try await sut.reveal(itemId: itemId, data: netdata, save: false)
        #expect(success)
        // this will be fixed if we use the new game / no game itemController switch
        #expect(root.itemController.itemDataModel.itemData[itemId] == nil)
        #expect(sut.gameModel.itemData[itemId] != nil)

        let success2 = try await sut.reveal(itemId: itemId, data: netdata, save: true)
        #expect(success2)
        #expect(root.itemController.itemDataModel.itemData[itemId] != nil)
    }
    
    @Test func createGameDataBackfillsMissingContentHash() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let itemController = root.itemController
        var exportController = ExportController(itemController: itemController)
        exportController.hubControllable = root
        let sut = GameController(itemController: itemController, exportController: exportController)

        root.itemController.itemDataModel.resetGame(start: true)
        let itemId = root.itemController.itemDataModel.items[0]
        let item = root.itemController.itemOrEmpty(for: itemId)

        // Point the item at a dedicated temp file with its own fresh fileId instead
        // of reusing the shared fixture's file/bookmark — the full suite runs many
        // tests concurrently against that shared fixture, which raced with this
        // test's own reset/reimport intermittently when the whole target ran.
        let tempURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).dat")
        try Data("backfill-test-content".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // A file attached locally through the picker never computes a content hash
        // (see the "Nil for legacy items whose data was never seen on this device"
        // note on FileUrl.contentHash) — simulate that here.
        item.fileUrl = FileUrl(fileId: UUID(), url: tempURL, location: .other, module: "photo", relativeUrl: nil)
        #expect(item.fileUrl?.contentHash == nil)
        let staleVersion = item.version

        let netdata = try await sut.createGameData(for: itemId)

        let backfilledFileUrl = try #require(root.itemController.itemOrEmpty(for: itemId).fileUrl)
        #expect(backfilledFileUrl.contentHash != nil)
        #expect(netdata.version != staleVersion)
        #expect(netdata.version == root.itemController.itemOrEmpty(for: itemId).version)
    }

    @Test func UpdateGame() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let itemController = root.itemController
        var exportController = ExportController(itemController: itemController)
        exportController.hubControllable = root
        let sut = GameController(itemController: itemController, exportController: exportController)

        root.itemController.itemDataModel.resetGame(start: true)

        let itemId = root.itemController.itemDataModel.items[0]
        let version = root.itemController.itemOrEmpty(for: itemId).version
        let netdata = try await sut.createGameData(for: itemId)
        #expect(netdata.id == itemId)
        #expect(netdata.type == NetworkModules.photo)
        #expect(netdata.version == version)
        let fileUrl = root.itemController.itemOrEmpty(for: itemId).fileUrl
        root.itemController.itemOrEmpty(for: itemId).fileUrl = nil
        let updatedVersion = root.itemController.itemOrEmpty(for: itemId).version
        #expect(updatedVersion != version)

        try await sut.updateGame(data: netdata, hide: false, deep: true)
        // check again if we use the new game / no game itemController switch will fix it
        #expect(root.itemController.itemOrEmpty(for: itemId).fileUrl == fileUrl)
    }
}

private extension GameControllerTests {
    static func setupPhoto() async throws -> PhotoRootModel {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        await root.gameController.reset()

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.photoTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value

        #expect(root.itemController.itemDataModel.items.count == 3)
        return root
    }
}
