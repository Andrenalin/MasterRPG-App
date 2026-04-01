// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels
import Observation
import PDFKit

@MainActor @Observable
final class PdfContentExtractionModel {

    var isExtracting: Bool = false
    var extractingProgress: [BlockGenModel] = []
    var pageProgress: PdfAnalysisProgress?
    var lastError: String?

    private let analyzer: PdfContentExtractor

    init() {
        analyzer = PdfContentExtractor()
    }

    /// Analyzes PDF with streaming progress updates
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Final summary analysis, or nil if analysis fails
    func extractWithProgress(from pdfDocument: PDFDocument) async -> [BlockGenModel] {

        isExtracting = true
        extractingProgress = []
        lastError = nil

        defer {
            isExtracting = false
            extractingProgress = []
        }

        do {
            let content = try await analyzer.extractWithProgress(from: pdfDocument) { [weak self] partial in
                self?.extractingProgress = partial
            }
            return content
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

#endif
