// @copyright André Trettin

import CoreData
import SwiftData
import Foundation
import Testing

@testable import CoreRPG

struct SwiftDataControllerTests {

    @Test func fetchAddDeleteData() async throws {
        let modelContainer = try ModelContainer(for: TestDataModel.self, configurations: .init(for: TestDataModel.self, isStoredInMemoryOnly: true))
        
        let sut = SwiftDataController<TestModel, TestDataModel>(modelContainer: modelContainer)
        #expect(try await sut.fetch().isEmpty)
        
        let testId = UUID()
        let newModel = TestDataModel(uuid: testId, testName: "Mega")
        await sut.add(data: newModel)
        
        let updated = try await sut.fetch()
        try #require(updated.count == 1)
        #expect(updated[0].testName == "Mega")
        
        let fetched = try await sut.fetch(uuid: testId)
        try #require(fetched != nil)
        #expect(fetched!.testName == "Mega")
        
        try await sut.delete(uuid: testId)
        #expect(try await sut.fetch().isEmpty)
        
        await sut.delete(data: newModel)
    }
    
    @Test func fetchWithController() async throws {
        let modelContainer = try ModelContainer(for: TestDataModel.self, configurations: .init(for: TestDataModel.self, isStoredInMemoryOnly: true))
        
        let sut = SwiftDataController<TestModel, TestDataModel>(modelContainer: modelContainer)
        
        #expect(try await sut.fetch().isEmpty)
        
        let newModel = TestModel(id: UUID(), testName: "Mega")
        try await sut.replace(uuid: newModel.id, with: newModel) { model in
            TestDataModel(uuid: model.id, testName: model.testName)
        } updater: { model, data in
            data.uuid = model.id
            data.testName = model.testName
        }

        let result = try await sut.fetch()
        try #require(result.count == 1)
        #expect(result[0].testName == newModel.testName)

        newModel.testName = "2nd Mega"
        try await sut.replace(uuid: newModel.id, with: newModel) { model in
            TestDataModel(uuid: model.id, testName: model.testName)
        } updater: { model, data in
            data.uuid = model.id
            data.testName = model.testName
        }

        let updatedResult = try await sut.fetch()
        try #require(updatedResult.count == 1)
        #expect(updatedResult[0].testName == newModel.testName)

        try await sut.delete(uuid: newModel.id)
        #expect(try await sut.fetch().isEmpty)
    }
}

@Model
fileprivate final class TestDataModel: SwiftDataType, @unchecked Sendable {
    init(uuid: UUID, testName: String) {
        self.uuid = uuid
        self.testName = testName
    }
    
    var uuid: UUID?
    var testName: String
}

@Observable
fileprivate final class TestModel: @unchecked Sendable {
    init(id: UUID, testName: String) {
        self.id = id
        self.testName = testName
    }
    
    var id: UUID
    var testName: String
}
