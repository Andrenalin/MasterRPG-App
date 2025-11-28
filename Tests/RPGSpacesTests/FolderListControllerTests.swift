// @copyright André Trettin

@testable import AndrenalinKit
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct FolderListControllerTests {

    @Test @MainActor func addFoldersAndItems() async throws {
        let root = try await MockRoot.importTestData()
        let convertController = ConvertController(itemController: root.itemController, editController: root.editController)

        #expect(root.itemController.itemDataModel.items.count == 1)
        let model = root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        model.fileUrl = FileUrl(fileId: model.id, url: URL(filePath: "/Rollenspiel/Example/3dmodel/3ditem.usdz"), location: .other, module: "Test", relativeUrl: nil)
        await convertController.checkFolders()
        try #require(root.itemController.itemDataModel.items.count == 4)
        // structure test in converterController
        
        let sut = root.folderListController
        
        var items = sut.displayItems
        try #require(items.count == 0)
        
        sut.resetFilter()
        items = sut.displayItems
        try #require(items.count == 1)
        #expect(items[0].model.name == "3D Item")
        
        sut.listDisplayModel.listMode = .folder
        sut.resetFilter()

        items = sut.displayItems
        try #require(items.count == 1)
        #expect(items[0].model.name == "Rollenspiel")
        
        sut.toggleFolder(item: items[0])
        items = sut.displayItems
        try #require(items.count == 2)
        #expect(items[0].model.name == "Rollenspiel")
        #expect(items[1].model.name == "Example")

        sut.toggleFolder(item: items[1])
        items = sut.displayItems
        try #require(items.count == 3)
        #expect(items[0].model.name == "Rollenspiel")
        #expect(items[1].model.name == "Example")
        #expect(items[2].model.name == "3dmodel")

        sut.toggleFolder(item: items[2])
        items = sut.displayItems
        try #require(items.count == 4)
        #expect(items[0].model.name == "Rollenspiel")
        #expect(items[1].model.name == "Example")
        #expect(items[2].model.name == "3dmodel")
        #expect(items[3].model.name == "3D Item")
        
        sut.listDisplayModel.listMode = .list
        sut.resetFilter()
        items = sut.displayItems
        try #require(items.count == 1)
        #expect(items[0].model.name == "3D Item")
    }
}
