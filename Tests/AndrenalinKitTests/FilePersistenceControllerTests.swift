// @copyright André Trettin

import Foundation
import Testing

@testable import AndrenalinKit

struct FilePersistenceControllerTests {

    @Test func loadSaveInMemory() async throws {
        let sut = FilePersistenceController(name: "MegaTest", persistence: .memory, dataExtension: nil)

        #expect(await sut.load().isEmpty)

        let data = [DataModel(id: UUID(), data: Data())]
        await sut.save(data: data)

        let loadedData = await sut.load()
        try #require(loadedData.count == 1)
        #expect(loadedData[0].id == data[0].id)
        #expect(loadedData[0].data == data[0].data)
    }

    @Test func loadSaveInStore() async throws {
        let sut = FilePersistenceController(name: "MegaTest", persistence: .store, dataExtension: nil)
        await sut.remove()

        #expect(await sut.load().isEmpty)

        let data = [DataModel(id: UUID(), data: Data())]
        await sut.save(data: data)

        let loadedData = await sut.load()
        try #require(loadedData.count == 1)
        #expect(loadedData[0].id == data[0].id)
        #expect(loadedData[0].data == data[0].data)

        await sut.remove()
        #expect(await sut.load().isEmpty)
    }

    @Test func externalData() async throws {
        let sut = FilePersistenceController(name: "MegaTest", persistence: .memory, dataExtension: "test")
        try await sut.removeData(for: "uuid")

        let saveData = String("save").data(using: .utf8)
        try #require(saveData != nil)
        try await sut.saveData(saveData.unsafelyUnwrapped, for: "uuid")

        let loadedData = try await sut.loadData(for: "uuid")
        try #require(loadedData != nil)

        let loadData = String(data: loadedData.unsafelyUnwrapped, encoding: .utf8)
        #expect(loadData == "save")

        try await sut.removeData(for: "uuid")
        let reloaded = try? await sut.loadData(for: "uuid")
        #expect(reloaded == nil)
    }
}
