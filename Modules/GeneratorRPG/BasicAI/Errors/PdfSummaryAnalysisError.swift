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
                // Subject-neutral: the table, character and extraction runs throw it too.
                // See CODE_AUDIT_29 §5.18.
                localized: "Apple Intelligence is not available. Turn it on in Settings to use this feature.",
                bundle: .module
            )
        case .generationFailed(let details):
            return String(localized: "Failed to generate summary analysis: \(details)", bundle: .module)
        }
    }
}

#endif
