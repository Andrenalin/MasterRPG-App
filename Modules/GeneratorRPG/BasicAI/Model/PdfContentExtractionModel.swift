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
        lastError = nil

        defer {
            isExtracting = false
        }

        do {
            return try await analyzer.extractWithProgress(from: pdfDocument, resultModel: resultModel)
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
