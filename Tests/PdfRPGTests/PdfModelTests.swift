// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
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

    // CODE_AUDIT_28 §7.12: `==` on an entry includes its CRDT clocks and actor ids, which a
    // rebuild from Core Data regenerates, so a bookmarked PDF never counted as unchanged.
    @Test func isSameIgnoresRegeneratedEntryClocks() async throws {
        let entryId = UUID()
        let original = PdfEntryModel(id: entryId, name: "Intro", content: "Text", pageNumber: "1", bounds: .zero)
        let rebuilt = PdfEntryModel(id: entryId, name: "Intro", content: "Text", pageNumber: "1", bounds: .zero)
        let local = PdfModel(id: UUID(), name: "Book", entries: [original])
        let remote = local.copy()
        remote.entries_ = CRDTDataUpdate(wrappedValue: [rebuilt], update: local.entries_.$update)

        #expect(local.isSame(remote))

        remote.entries_ = CRDTDataUpdate(wrappedValue: [PdfEntryModel(id: entryId, name: "Other", content: "Text", pageNumber: "1", bounds: .zero)], update: local.entries_.$update)
        #expect(!local.isSame(remote))
    }
}
#endif
