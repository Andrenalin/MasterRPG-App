// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.13: a file block is exported only if the import can read it back
/// (CODE_AUDIT_21 §5.8).
@Suite("Export block limit")
struct ExportBlockLimitTests {
    @Test("A file block fits the import limit up to exactly the limit")
    func blockLimit() {
        let limit = InputStream.maxSingleBlockSize

        #expect(SimpleNullExportController.fitsImportBlock(0))
        #expect(SimpleNullExportController.fitsImportBlock(limit))
        #expect(!SimpleNullExportController.fitsImportBlock(limit + 1))
    }
}
