// @copyright André Trettin

#if !os(tvOS)
import Foundation
import PDFKit

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
