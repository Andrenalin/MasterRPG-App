// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PhotoRPG

struct GameControllerTests {
    @Test func HasItem() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController

        // random id must be false
        let randomId = UUID()
        var result = await sut.hasItem(id: randomId, version: 0)
        #expect(!result)
        await #expect(sut.gameModel.itemData[randomId] == nil)

        let itemId = await root.itemController.itemDataModel.items[0]
        let item = await root.itemController.itemOrEmpty(for: itemId)
        let version = item.version
        result = await sut.hasItem(id: itemId, version: version + 1)
        #expect(!result)
        await #expect(sut.gameModel.itemData[itemId] == nil)

        result = await sut.hasItem(id: root.itemController.itemDataModel.items[0], version: version)
        #expect(result)
        await #expect(sut.gameModel.itemData[itemId] != nil)

        result = await sut.hasItem(id: root.itemController.itemDataModel.items[0], version: version + 1)
        #expect(!result)
        await #expect(sut.gameModel.itemData[itemId] != nil)
    }
    
    @Test func SetCurrent() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController

        // random id must be false
        let randomId = UUID()
        #expect(await sut.setCurrent(itemId: randomId) == false)
        await #expect(sut.currentId != randomId)

        let itemId = await root.itemController.itemDataModel.items[0]
        #expect(await sut.setCurrent(itemId: itemId))
        await #expect(sut.currentId == itemId)
        await #expect(sut.gameModel.items[0] == itemId)

        let secondId = await root.itemController.itemDataModel.items[1]
        #expect(await sut.setCurrent(itemId: secondId))
        await #expect(sut.currentId == secondId)
        await #expect(sut.gameModel.items[0] == secondId)
        await #expect(sut.gameModel.items[1] == itemId)

        #expect(await sut.setCurrent(itemId: itemId))
        await #expect(sut.currentId == itemId)
        await #expect(sut.gameModel.items[0] == itemId)
        await #expect(sut.gameModel.items[1] == secondId)

        await sut.reset()
        await #expect(sut.gameModel.items.isEmpty)
        await #expect(sut.gameModel.itemData.isEmpty)
        await #expect(sut.currentId != itemId)
    }
    
    @Test func Report() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let sut = root.gameController

        let itemId = await root.itemController.itemDataModel.items[0]
        let playerId = UUID()
        await sut.report(itemId: itemId, for: playerId)
        await #expect(root.itemController.itemOrEmpty(for: itemId).players == [playerId])

        #expect(await sut.setCurrent(itemId: itemId))
        await sut.report(itemId: itemId, for: playerId)
        await #expect(root.itemController.itemOrEmpty(for: itemId).players == [playerId])
        await sut.report(itemId: itemId, for: playerId)
        await #expect(root.itemController.itemOrEmpty(for: itemId).players.count == 1)
    }
    
    @Test func CreateGameData() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let rootManager = await RootManager.preview(fake: root.rootController)
        let sut = await GameController(rootManager: rootManager, itemController: root.itemController, exportController: root.exportController)

        let itemId = await root.itemController.itemDataModel.items[0]
        let version = await root.itemController.itemOrEmpty(for: itemId).version
        let netdata = try await sut.createGameData(for: itemId)
        #expect(netdata.id == itemId)
        #expect(netdata.type == NetworkModules.photo)
        #expect(netdata.version == version)

        await root.itemController.delete(itemId: itemId)
        await #expect(root.itemController.itemDataModel.itemData[itemId] == nil)

        let success = try await sut.reveal(itemId: itemId, data: netdata, save: false)
        #expect(success)
        // this will be fixed if we use the new game / no game itemController switch
        await #expect(root.itemController.itemDataModel.itemData[itemId] == nil)
        await #expect(sut.gameModel.itemData[itemId] != nil)

        let success2 = try await sut.reveal(itemId: itemId, data: netdata, save: true)
        #expect(success2)
        await #expect(root.itemController.itemDataModel.itemData[itemId] != nil)
    }
    
    @Test func UpdateGame() async throws {
        let root = try await GameControllerTests.setupPhoto()
        let rootManager = await RootManager.preview(fake: root.rootController)
        let sut = await GameController(rootManager: rootManager, itemController: root.itemController, exportController: root.exportController)

        let itemId = await root.itemController.itemDataModel.items[0]
        let version = await root.itemController.itemOrEmpty(for: itemId).version
        let netdata = try await sut.createGameData(for: itemId)
        #expect(netdata.id == itemId)
        #expect(netdata.type == NetworkModules.photo)
        #expect(netdata.version == version)
        let fileUrl = await root.itemController.itemOrEmpty(for: itemId).fileUrl
        await root.itemController.itemOrEmpty(for: itemId).fileUrl = nil
        let updatedVersion = await root.itemController.itemOrEmpty(for: itemId).version
        #expect(updatedVersion != version)

        try await sut.updateGame(data: netdata, hide: false, deep: true)
        // check again if we use the new game / no game itemController switch will fix it
        await #expect(root.itemController.itemOrEmpty(for: itemId).fileUrl == fileUrl)
    }
}

private extension GameControllerTests {
    static func setupPhoto() async throws -> PhotoRootModel {
        let root = await PhotoRootModel.testRoot()
        await root.itemController.resetData()
        await root.gameController.reset()

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.photoTestData, withExtension: "gmz").unsafelyUnwrapped
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value

        #expect(await root.itemController.itemDataModel.items.count == 3)
        return root
    }
}
#endif
