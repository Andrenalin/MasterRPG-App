// @copyright André Trettin

import CoreData
@preconcurrency import SwiftData
import Foundation
import Testing

@testable import CoreRPG

struct SwiftDataControllerTests {

    @Test func fetchAddDeleteData() async throws {
        let modelContainer = try ModelContainer(for: TestDataModel.self, configurations: .init(for: TestDataModel.self, isStoredInMemoryOnly: true))
        
        let sut = SwiftDataController<TestModel, TestDataModel>(modelContainer: modelContainer)
        #expect(try await sut.fetch(transform: TestDataSnapshot.init(data:)).isEmpty)
        
        let testId = UUID()
        let newModel = TestModel(id: testId, testName: "Mega")
        try await sut.replace(uuid: newModel.id, with: newModel) { model in
            TestDataModel(uuid: model.id, testName: model.testName)
        } updater: { model, data in
            data.uuid = model.id
            data.testName = model.testName
        }
        
        let updated = try await sut.fetch(transform: TestDataSnapshot.init(data:))
        try #require(updated.count == 1)
        #expect(updated[0].testName == "Mega")
        
        let fetched = try await sut.fetch(uuid: testId, transform: TestDataSnapshot.init(data:))
        try #require(fetched != nil)
        #expect(fetched!.testName == "Mega")
        
        try await sut.delete(uuid: testId)
        #expect(try await sut.fetch(transform: TestDataSnapshot.init(data:)).isEmpty)
    }
    
    @Test func fetchWithController() async throws {
        let modelContainer = try ModelContainer(for: TestDataModel.self, configurations: .init(for: TestDataModel.self, isStoredInMemoryOnly: true))
        
        let sut = SwiftDataController<TestModel, TestDataModel>(modelContainer: modelContainer)
        
        #expect(try await sut.fetch(transform: TestDataSnapshot.init(data:)).isEmpty)
        
        let newModel = TestModel(id: UUID(), testName: "Mega")
        try await sut.replace(uuid: newModel.id, with: newModel) { model in
            TestDataModel(uuid: model.id, testName: model.testName)
        } updater: { model, data in
            data.uuid = model.id
            data.testName = model.testName
        }

        let result = try await sut.fetch(transform: TestDataSnapshot.init(data:))
        try #require(result.count == 1)
        #expect(result[0].testName == newModel.testName)

        newModel.testName = "2nd Mega"
        try await sut.replace(uuid: newModel.id, with: newModel) { model in
            TestDataModel(uuid: model.id, testName: model.testName)
        } updater: { model, data in
            data.uuid = model.id
            data.testName = model.testName
        }

        let updatedResult = try await sut.fetch(transform: TestDataSnapshot.init(data:))
        try #require(updatedResult.count == 1)
        #expect(updatedResult[0].testName == newModel.testName)

        try await sut.delete(uuid: newModel.id)
        #expect(try await sut.fetch(transform: TestDataSnapshot.init(data:)).isEmpty)
    }
}

@Model
fileprivate final class TestDataModel: SwiftDataType {
    init(uuid: UUID, testName: String) {
        self.uuid = uuid
        self.testName = testName
    }
    
    var uuid: UUID?
    var testName: String
}

private struct TestDataSnapshot: Sendable {
    init(data: TestDataModel) {
        self.uuid = data.uuid
        self.testName = data.testName
    }

    let uuid: UUID?
    let testName: String
}

// Deliberately not @MainActor, unlike CLAUDE.md's mandate for @Observable
// classes: `SwiftDataController.replace(uuid:with:mapper:updater:)` takes
// synchronous, non-isolated `@Sendable` mapper/updater closures over `Model`
// (see `ModelType = Observable & Sendable`) — isolating this fixture to
// @MainActor makes every one of those closures' property accesses illegal
// ("main actor-isolated property ... can not be referenced from a Sendable
// closure"), since a @Sendable closure may run off the actor that isolates
// its captures. `SwiftDataController` has no production caller to check this
// contract against elsewhere in the codebase. See CODE_AUDIT_10 §3.5.
@Observable
fileprivate final class TestModel: @unchecked Sendable {
    init(id: UUID, testName: String) {
        self.id = id
        self.testName = testName
    }

    var id: UUID
    var testName: String
}
