// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import SpaceRPG

struct ConverterControllerTests {

    @Test func checkFolders_generate_entries_and_links() async throws {
        let root = try await MockRoot.importTestData()
        let sut = ConvertController(itemController: root.itemController, editController: root.editController)

        #expect(await root.itemController.itemDataModel.items.count == 1)
        let model = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        model.fileUrl = FileUrl(fileId: model.id, url: URL(filePath: "/Rollenspiel/Example/3dmodel/3ditem.usdz"), location: .other, module: "Test", relativeUrl: nil)
        
        await sut.createFilepathFoldersAndCollections(reportModel: ValidateRepairModel())
        try #require(await root.itemController.itemDataModel.items.count == 4)
        
        let model1 = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        #expect(model1.name == "3D Item")

        let model2 = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[1])
        #expect(model2.name == "3dmodel")

        let model3 = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[2])
        #expect(model3.name == "Example")

        let model4 = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[3])
        #expect(model4.name == "Rollenspiel")
        
        #expect(model4.parentId == nil)
        #expect(model3.parentId == model4.id)
        #expect(model2.parentId == model3.id)
        #expect(model1.parentId == model2.id)
        
        try #require(model4.entries.count == 1)
        #expect(model4.entries[0].childId == model3.id)

        try #require(model3.entries.count == 1)
        #expect(model3.entries[0].childId == model2.id)

        try #require(model2.entries.count == 1)
        #expect(model2.entries[0].childId == model1.id)

        try #require(model1.entries.count == 0)
        
        await sut.createFilepathFoldersAndCollections(reportModel: ValidateRepairModel())
        try #require(await root.itemController.itemDataModel.items.count == 4)

        #expect(model4.parentId == nil)
        #expect(model4.entries[0].childId == model3.id)
        #expect(model4.name == "Rollenspiel")

        #expect(model3.parentId == model4.id)
        #expect(model3.entries[0].childId == model2.id)
        #expect(model3.name == "Example")

        #expect(model2.parentId == model3.id)
        #expect(model2.entries[0].childId == model1.id)
        #expect(model2.name == "3dmodel")

        #expect(model1.parentId == model2.id)
        try #require(model1.entries.count == 0)
        #expect(model1.name == "3D Item")
    }
}
