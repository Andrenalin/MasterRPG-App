// @copyright André Trettin

import CoreGraphics
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_Since_3.0.1 §3.4: a write intent the user dismissed while it waited for the
/// database must not write once the store is ready.
@Suite("Database gate cancellation")
@MainActor
struct DatabaseGateCancellationTests {
    @Test("A cancelled write intent throws CancellationError instead of continuing")
    func cancelledWaitThrows() async {
        let intent = Task { @MainActor in
            try await requireReadyDatabase()
        }
        intent.cancel()
        let result = await intent.result
        // Whether the database is ready in this test process or not: before the fix a ready
        // database let the write go on, and a missing one reported "not ready".
        #expect(throws: CancellationError.self) { try result.get() }
    }
}

/// CODE_AUDIT_Since_3.0.1 §3.2: the PDF export lays its pages out off the main actor.
@Suite("Entity PDF export")
@MainActor
struct EntityPdfExportTests {
    @Test("A long text becomes a multi-page PDF named after the item id")
    func longTextBecomesPages() async throws {
        let id = UUID()
        let description = String(repeating: "The dragon sleeps under the mountain. ", count: 400)
        let url = try await EntitySummaryExport.pdf(id: id, module: .weather, name: "Storm", description: description)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == "\(id.uuidString).pdf")
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages > 1)
    }
}
