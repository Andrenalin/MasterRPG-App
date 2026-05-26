// @copyright André Trettin

import Foundation
import FoundationModels
import Observation
import PDFKit

@MainActor @Observable
final class PdfSummaryAnalysisModel {

    var isAnalyzing: Bool = false
    let resultModel: PdfSummaryAnalyzyerResultModel
    var lastError: String?

    private let analyzer: PdfSummaryAnalyzer

    init() {
        analyzer = PdfSummaryAnalyzer()
        resultModel = PdfSummaryAnalyzyerResultModel()
    }

    /// Analyzes PDF with streaming progress updates
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Final summary analysis, or nil if analysis fails
    func analyzeWithProgress(from pdfDocument: PDFDocument, outputLanguage: String = "English") async -> PdfSummaryAnalysis? {
        isAnalyzing = true
        resultModel.analysisProgress = nil
        resultModel.pageProgress = nil
        lastError = nil

        defer {
            isAnalyzing = false
        }

        do {
            return try await analyzer.analyzeWithProgress(from: pdfDocument, resultModel: resultModel, outputLanguage: outputLanguage)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Clears the last error message
    func clearError() {
        lastError = nil
    }
}
