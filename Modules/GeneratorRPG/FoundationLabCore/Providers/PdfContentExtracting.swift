// @copyright André Trettin

#if !os(tvOS)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

/// Protocol for PDF content extraction services
@MainActor
public protocol PdfContentExtracting: Sendable {
    /// Extracts structured content from a PDF document
    /// - Parameter pdfDocument: The PDF document to extract from
    /// - Returns: Structured extracted content
    /// - Throws: PdfExtractionError if extraction fails
    func extract(from pdfDocument: PDFDocument) async throws -> PdfExtractedContent

    /// Extracts content with streaming progress updates
    /// - Parameters:
    ///   - pdfDocument: The PDF document to extract from
    ///   - onPartialContent: Callback for incremental updates during extraction
    /// - Returns: Final extracted content
    func extractWithProgress(
        from pdfDocument: PDFDocument,
        onPartialContent: @escaping @MainActor @Sendable (PdfExtractedContent.PartiallyGenerated) -> Void
    ) async throws -> PdfExtractedContent
}

/// Errors that can occur during PDF extraction
public enum PdfExtractionError: LocalizedError {
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
            return "Apple Intelligence is not available. PDF content extraction requires it."
        case .generationFailed(let details):
            return "Failed to generate structured content: \(details)"
        }
    }
}

#endif
