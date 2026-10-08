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

    private let analyzer: PdfContentExtractor

    init() {
        analyzer = PdfContentExtractor()
        resultModel = PdfContentExtractionResultModel()
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
            let blocks = try await analyzer.extractWithProgress(from: pdfDocument, resultModel: resultModel)
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
