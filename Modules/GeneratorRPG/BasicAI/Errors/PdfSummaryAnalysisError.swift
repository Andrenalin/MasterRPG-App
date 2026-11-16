// @copyright André Trettin

#if !os(tvOS)
import Foundation
import PDFKit

/// Errors that can occur during PDF summary analysis
public enum PdfSummaryAnalysisError: LocalizedError {
    case emptyDocument
    case textExtractionFailed
    case modelUnavailable
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return String(
                localized: "The PDF document is empty or contains no readable text.",
                bundle: .module
            )
        case .textExtractionFailed:
            return String(localized: "Failed to extract text from the PDF document.", bundle: .module)
        case .modelUnavailable:
            return String(
                localized: "Apple Intelligence is not available. PDF summary analysis requires it.",
                bundle: .module
            )
        case .generationFailed(let details):
            return String(localized: "Failed to generate summary analysis: \(details)", bundle: .module)
        }
    }
}

#endif
