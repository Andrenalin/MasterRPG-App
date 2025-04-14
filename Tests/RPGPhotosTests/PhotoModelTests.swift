// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import Testing

@testable import RPGPhotos

struct PhotoModelTests {
    func setUp() async throws -> PhotoModel {
        PhotoModel(id: UUID(), name: "Hello", degrees: 90.0)
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.degrees == sut.degrees)

        #expect(d.degrees == a.degrees)
        #expect(d.degrees_.rawValue != sut.degrees_.rawValue)

        let merged = sut.merge(a)
        #expect(merged == sut)
        #expect(merged == a)
    }

    @Test func changeValues() async throws {
        let sut = try await setUp()
        let a = sut.copy()
        a.degrees = 180.0
        #expect(a.degrees == 180.0)
        #expect(sut.degrees == 90.0)

        let b = sut.copy()
        var merged = b.merge(a)
        #expect(merged.degrees == 180.0)


        a.degrees = 270.0
        merged = b.merge(a)
        #expect(merged.degrees == 270.0)
    }
    
    @Test func version() async throws  {
        let sut = try await setUp()
        let a = sut.copy()
        #expect(a.version == sut.version)
    }
}
#endif
