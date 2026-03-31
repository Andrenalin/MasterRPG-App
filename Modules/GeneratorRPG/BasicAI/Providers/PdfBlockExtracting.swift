// @copyright André Trettin

#if !os(tvOS)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

/// Protocol for PDF block extraction services
@MainActor
public protocol PdfBlockExtracting: Sendable {
    /// Extracts structured blocks from a PDF document
    /// - Parameter pdfDocument: The PDF document to extract from
    /// - Returns: Array of extracted blocks
    /// - Throws: PdfExtractionError if extraction fails
    //func extract(from pdfDocument: PDFDocument) async throws -> [BlockGenModel]

    /// Extracts blocks with streaming progress updates
    /// - Parameters:
    ///   - pdfDocument: The PDF document to extract from
    ///   - onPartialBlocks: Callback for incremental updates during extraction
    /// - Returns: Final extracted blocks
    func extractWithProgress(
        from pdfDocument: PDFDocument,
        onPartialBlocks: @escaping @MainActor @Sendable ([BlockGenModel]) -> Void
    ) async throws -> [BlockGenModel]
}

#endif
