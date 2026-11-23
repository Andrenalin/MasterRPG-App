// @copyright André Trettin

#if !os(tvOS)

import Foundation
import PDFKit
import Testing

@testable import GeneratorRPG

/// CODE_AUDIT_28 §5.22: a failed or partial extraction was handed on as a result, the parent
/// replaced the screen (and its error banner) and the PDF looked like it had no text.
@MainActor
@Suite("PDF content extraction result")
struct PdfContentExtractionModelTests {
    private struct ExtractionFailure: Error {}

    @Test("A clean extraction delivers its blocks")
    func cleanExtractionDelivers() async {
        let model = PdfContentExtractionModel { _, _ in [BlockEntryGenModel(title: "A", content: "Text")] }

        let blocks = await model.extractForDelivery(from: PDFDocument())

        #expect(blocks?.count == 1)
        #expect(model.lastError == nil)
    }

    @Test("A PDF without text delivers no blocks, which is a real result")
    func emptyExtractionDelivers() async {
        let model = PdfContentExtractionModel { _, _ in [] }

        #expect(await model.extractForDelivery(from: PDFDocument()) == [])
    }

    @Test("A failed extraction delivers nothing and keeps its error")
    func failureIsNotDelivered() async {
        let model = PdfContentExtractionModel { _, _ in throw ExtractionFailure() }

        let blocks = await model.extractForDelivery(from: PDFDocument())

        #expect(blocks == nil)
        #expect(model.lastError != nil)
    }

    @Test("Lost pages keep the screen so the banner can name them")
    func lostPagesAreNotDelivered() async {
        let model = PdfContentExtractionModel { _, resultModel in
            resultModel.setFailedPages([2, 3])
            return [BlockEntryGenModel(title: "A", content: "Text")]
        }

        let blocks = await model.extractForDelivery(from: PDFDocument())

        #expect(blocks == nil)
        #expect(model.lastError != nil)
    }
}
#endif
