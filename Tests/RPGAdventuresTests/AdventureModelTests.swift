// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import Testing

@testable import RPGAdventures

struct AdventureModelTests{
    func setUp() async throws -> AdventureModel {
        AdventureModel(
            id: UUID(),
            name: "My Name",
            description: "My Desc",
            tags: ["Map"],
            category: .scenario,
            displayState: 23,
            photoId: UUID()
        )
    }

    @Test func assignAndDuplicate()  async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == "\(a.name) Copy")
        #expect(d.description == a.description)
        #expect(d.tags == a.tags)
        #expect(d.category == a.category)
        #expect(d.displayState == a.displayState)
        #expect(d.photoId == a.photoId)
    }

    @Test func changeValues() async throws {
        let sut = try await setUp()
        let a = sut.copy()
        #expect(sut.isSame(a) == true)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        sut.description = "My Content"
        sut.name = "Better"
        a.description = "Take this"
        a.tags = ["Better"]
        sut.category = .campaign
        a.displayState = 100

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.description == a.description)
        #expect(m1.tags == a.tags)
        #expect(m1.category == sut.category)
        #expect(m1.displayState == sut.displayState)

        let m2 = sut.merge(a)
        #expect(m2.id == sut.id)
        #expect(m2.name == sut.name)
        #expect(m2.description == a.description)
        #expect(m2.tags == a.tags)
        #expect(m2.category == sut.category)
        #expect(m2.displayState == a.displayState)

        #expect(sut.isSame(a) == false)
        #expect(m1.isSame(m2) == true)
    }
}
#endif
