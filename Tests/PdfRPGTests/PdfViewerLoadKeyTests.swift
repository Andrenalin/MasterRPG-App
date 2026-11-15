// @copyright André Trettin

import Foundation
import Testing

@testable import PdfRPG

@Suite("Pdf viewer load key")
struct PdfViewerLoadKeyTests {
    @Test("A new file version of the same item is a different key")
    func newVersionChangesTheKey() {
        let id = UUID()

        #expect(PdfViewerLoadKey(id: id, version: 1) != PdfViewerLoadKey(id: id, version: 2))
    }

    @Test("The same item and version is the same key")
    func sameVersionKeepsTheKey() {
        let id = UUID()

        #expect(PdfViewerLoadKey(id: id, version: 3) == PdfViewerLoadKey(id: id, version: 3))
    }
}
