// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

struct FileUrlDataControllerTests {

    @Test func readAddSaveReread() async throws {
        let fake = FakeFileUrAccessible()
        let sut = await FileUrlDataController(moduleFolder: "MegaModules", fileTypes: [.rpgDocument], filenameExtension: ".rpg", fileUrlAccess: fake)

        await #expect(sut.model.folders.isEmpty)
    }
}

fileprivate struct FakeFileUrAccessible: FileUrlAccessible {
    func saveFileUrl(fileUrl: FileUrl) async {}
}

fileprivate struct TestDataModel: Identifiable, Storeable, Codable {
    let id: UUID
    let name: String
}
