// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import PdfRPG

@MainActor
struct PdfModelTests {
    func setUp() async throws -> PdfModel {
        PdfModel(id: UUID(), name: "Hello")
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.fileUrl == sut.fileUrl)

        #expect(d.fileUrl == a.fileUrl)
        #expect(d.fileUrl_.update != sut.fileUrl_.update)

        let merged = sut.merge(a)
        #expect(merged == sut)
        #expect(merged != d)
    }
}
#endif
