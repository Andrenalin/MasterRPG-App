// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResourcesDebug
import Testing

@testable import RPGPdfs

struct ImportControllerTests {
    @Test func importing() async throws {
        let root = await PdfRootModel.testRoot()
        await root.itemController.resetData()

        let sut = root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.pdfTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(await root.itemController.itemDataModel.items.count == 1)
    }
}
