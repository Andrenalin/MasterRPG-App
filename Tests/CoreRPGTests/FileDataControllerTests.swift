// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

struct FileDataControllerTests {

    @Test func readAddSaveReread() async throws {
        let sut = FileDataController<TestDataModel>(name: "MegaTest", type: .memory)

        await sut.fetch()
        let testData = TestDataModel(id: UUID(), name: "Test")
        await sut.addNew(data: testData)
        let readData = await sut.read(id: testData.id)

        try #require(readData != nil)
        #expect(readData!.name == "Test")

        await sut.save()
        try? await sut.delete(id: testData.id)

        let readDataAgain = await sut.read(id: testData.id)
        #expect(readDataAgain == nil)

        await sut.fetch()
        let readDataAfterFetch = await sut.read(id: testData.id)
        try #require(readDataAfterFetch != nil)
        #expect(readDataAfterFetch!.name == "Test")
    }
}

fileprivate struct TestDataModel: Identifiable, Storable, Codable {
    let id: UUID
    let name: String
}
