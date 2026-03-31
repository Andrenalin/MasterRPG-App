// @copyright André Trettin

#if !os(tvOS)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Request

public struct PdfExtractionRequest: CapabilityRequest {
    public let pdfData: Data?
    public let pdfUrl: URL?
    public let useStreaming: Bool

    public init(pdfData: Data? = nil, pdfUrl: URL? = nil, useStreaming: Bool = false) {
        self.pdfData = pdfData
        self.pdfUrl = pdfUrl
        self.useStreaming = useStreaming
    }
}

// MARK: - Result

public struct PdfExtractionResult: CapabilityResult {
    public let content: PdfExtractedContent

    public init(content: PdfExtractedContent) {
        self.content = content
    }
}

// MARK: - Use Case

/// Use case for extracting structured content from PDF documents
public struct ExtractPdfContentUseCase: CapabilityUseCase {

    public static let descriptor = CapabilityDescriptor(
        id: "foundation-models.extract-pdf-content",
        displayName: "PDF Content Extraction",
        summary: "Extracts structured metadata from RPG PDF documents using Foundation Models."
    )

    private let provider: any PdfContentExtracting

    public init(provider: any PdfContentExtracting) {
        self.provider = provider
    }

    @MainActor
    public init() {
        self.provider = FoundationModelsPdfContentExtractor()
    }

    public func execute(_ request: PdfExtractionRequest) async throws -> PdfExtractionResult {
        let pdfDocument: PDFDocument

        if let pdfData = request.pdfData {
            guard let doc = PDFDocument(data: pdfData) else {
                throw FoundationLabCoreError.invalidRequest("Could not create PDF document from data")
            }
            pdfDocument = doc
        } else if let pdfUrl = request.pdfUrl {
            guard let doc = PDFDocument(url: pdfUrl) else {
                throw FoundationLabCoreError.invalidRequest("Could not load PDF document from URL")
            }
            pdfDocument = doc
        } else {
            throw FoundationLabCoreError.invalidRequest("Either pdfData or pdfUrl must be provided")
        }

        let content = try await provider.extract(from: pdfDocument)
        return PdfExtractionResult(content: content)
    }

    // MARK: - Convenience Methods

    /// Extracts content from a PDF document with streaming progress
    /// - Parameters:
    ///   - pdfDocument: The PDF to analyze
    ///   - onProgress: Callback for incremental updates
    /// - Returns: Extracted content
    @MainActor
    public func extractWithProgress(
        from pdfDocument: PDFDocument,
        onProgress: @escaping @MainActor @Sendable (PdfExtractedContent.PartiallyGenerated) -> Void
    ) async throws -> PdfExtractedContent {
        return try await provider.extractWithProgress(
            from: pdfDocument,
            onPartialContent: onProgress
        )
    }

    /// Extracts content from a PDF document
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Extracted content
    @MainActor
    public func extract(from pdfDocument: PDFDocument) async throws -> PdfExtractedContent {
        return try await provider.extract(from: pdfDocument)
    }
}

#endif
