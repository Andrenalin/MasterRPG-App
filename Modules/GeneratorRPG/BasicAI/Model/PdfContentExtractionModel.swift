// @copyright André Trettin

import Foundation
import FoundationModels
import Observation
import PDFKit

@MainActor @Observable
final class PdfContentExtractionModel {

    var isExtracting: Bool = false
    let resultModel: PdfContentExtractionResultModel
    var lastError: String?

    /// Runs the extraction; tests replace it, the default asks the on-device model.
    private let extraction: @MainActor (PDFDocument, PdfContentExtractionResultModel) async throws -> [BlockEntryGenModel]

    init(
        extraction: (@MainActor (PDFDocument, PdfContentExtractionResultModel) async throws -> [BlockEntryGenModel])? = nil
    ) {
        let analyzer = PdfContentExtractor()
        self.extraction = extraction ?? { document, resultModel in
            try await analyzer.extractWithProgress(from: document, resultModel: resultModel)
        }
        resultModel = PdfContentExtractionResultModel()
    }

    /// The blocks of a clean extraction, or `nil` when it failed or lost pages: the error stays
    /// in `lastError` and the screen keeps its banner, instead of an empty or partial result
    /// replacing it as if the PDF had no text. A PDF without text extracts cleanly to no blocks.
    /// See CODE_AUDIT_28 §5.22.
    func extractForDelivery(from pdfDocument: PDFDocument) async -> [BlockEntryGenModel]? {
        let blocks = await extractWithProgress(from: pdfDocument)
        return lastError == nil ? blocks : nil
    }

    /// Extracts PDF content with streaming progress updates
    /// - Parameter pdfDocument: The PDF to extract
    /// - Returns: Final extracted blocks, or empty array if extraction fails
    func extractWithProgress(from pdfDocument: PDFDocument) async -> [BlockEntryGenModel] {
        isExtracting = true
        resultModel.extractionProgress = []
        resultModel.pageProgress = PdfAnalysisProgress(currentPage: 0, totalPages: 1)
        resultModel.setFailedPages([])
        lastError = nil

        defer {
            isExtracting = false
        }

        do {
            let blocks = try await extraction(pdfDocument, resultModel)
            // Some pages failed and the rest is returned: say which. See CODE_AUDIT_21 §5.28.
            if !resultModel.failedPages.isEmpty {
                let pages = resultModel.failedPages.map { $0.formatted() }.formatted(.list(type: .and))
                lastError = String(localized: "Pages that could not be analysed: \(pages)", bundle: .module)
            }
            return blocks
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Clears the last error message
    func clearError() {
        lastError = nil
    }
}
