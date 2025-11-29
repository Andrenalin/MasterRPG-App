// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import AudioRPG

struct AudioModelTests {
    func setUp() async throws -> AudioModel {
        AudioModel(id: UUID(), name: "Hello", description: "TestDesc", tags: ["tag1", "tag2"], category: .map, displayState: 0, fileUrl: nil, entries: [AudioEntryModel.empty])
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.name == "\(a.name) Copy")
        #expect(d.description == a.description)
        #expect(d.description_.rawValue != sut.description_.rawValue)
        #expect(d.tags == a.tags)
        #expect(d.category == a.category)
        #expect(d.displayState == a.displayState)
        #expect(d.fileUrl == a.fileUrl)
        #expect(d.entries.map { $0.audioId } == a.entries.map { $0.audioId })
        #expect(d.entries != a.entries)

        d.description = "New Desc"
        #expect(d.description == "New Desc")

        let merged = sut.merge(a)
        #expect(merged == sut)
        #expect(merged != d)

        let m2 = d.merge(sut)
        #expect(m2 == d)
    }

    @Test func ChangeValues() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a.name == "Hello")
        #expect(sut.category == .map)

        let b = sut
        var merged = b.merge(a)
        #expect(merged.category == .map)

        a.category = .adventure
        merged = b.merge(a)
        #expect(merged.category == .adventure)
    }
}
