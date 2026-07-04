// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PhotoRPG

@MainActor
struct GameControllerTests {
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
        let rootManager = RootManager.preview(fake: root.rootController)
        let itemController = root.itemController
        let exportController = ExportController(rootManager: rootManager, itemController: itemController)
        let sut = GameController(rootManager: rootManager, itemController: itemController, exportController: exportController)

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
    
    @Test func UpdateGame() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let rootManager = RootManager.preview(fake: root.rootController)
        let itemController = root.itemController
        let exportController = ExportController(rootManager: rootManager, itemController: itemController)
        let sut = GameController(rootManager: rootManager, itemController: itemController, exportController: exportController)

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

        #expect(root.itemController.itemDataModel.items.count == 6)
        return root
    }
}
#endif
