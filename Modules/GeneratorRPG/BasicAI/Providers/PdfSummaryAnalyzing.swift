// @copyright André Trettin

#if !os(tvOS)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

/// Protocol for PDF summary analysis services
@MainActor
public protocol PdfSummaryAnalyzing: Sendable {
    /// Analyzes PDF with streaming progress updates
    /// - Parameters:
    ///   - pdfDocument: The PDF document to analyze
    ///   - onPartialContent: Callback for incremental updates during analysis
    /// - Returns: Final summary analysis
    func analyzeWithProgress(
        from pdfDocument: PDFDocument,
        onPartialContent: @escaping @MainActor @Sendable (PdfSummaryAnalysis.PartiallyGenerated) -> Void
    ) async throws -> PdfSummaryAnalysis
}

/// Errors that can occur during PDF summary analysis
public enum PdfSummaryAnalysisError: LocalizedError {
    case emptyDocument
    case textExtractionFailed
    case contentTooLarge
    case modelUnavailable
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "The PDF document is empty or contains no readable text."
        case .textExtractionFailed:
            return "Failed to extract text from the PDF document."
        case .contentTooLarge:
            return "The PDF content is too large. Processing only the first portion."
        case .modelUnavailable:
            return "Apple Intelligence is not available. PDF summary analysis requires it."
        case .generationFailed(let details):
            return "Failed to generate summary analysis: \(details)"
        }
    }
}

#endif
