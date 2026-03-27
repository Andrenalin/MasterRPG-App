// @copyright André Trettin

#if !os(tvOS)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Request

public struct PdfBlockExtractionRequest: CapabilityRequest {
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

public struct PdfBlockExtractionResult: CapabilityResult {
    public let blocks: [BlockGenModel]

    public init(blocks: [BlockGenModel]) {
        self.blocks = blocks
    }
}

// MARK: - Use Case

/// Use case for extracting structured blocks from PDF documents
public struct ExtractPdfBlocksUseCase: CapabilityUseCase {

    public static let descriptor = CapabilityDescriptor(
        id: "foundation-models.extract-pdf-blocks",
        displayName: "PDF Block Extraction",
        summary: "Extracts structured content blocks from PDF documents using Foundation Models."
    )

    private let provider: any PdfBlockExtracting

    public init(provider: any PdfBlockExtracting) {
        self.provider = provider
    }

    @MainActor
    public init() {
        self.provider = FoundationModelsPdfBlockExtractor()
    }

    public func execute(_ request: PdfBlockExtractionRequest) async throws -> PdfBlockExtractionResult {
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

        let blocks = try await provider.extract(from: pdfDocument)
        return PdfBlockExtractionResult(blocks: blocks)
    }

    // MARK: - Convenience Methods

    /// Extracts blocks from a PDF document with streaming progress
    /// - Parameters:
    ///   - pdfDocument: The PDF to analyze
    ///   - onProgress: Callback for incremental updates
    /// - Returns: Extracted blocks
    @MainActor
    public func extractWithProgress(
        from pdfDocument: PDFDocument,
        onProgress: @escaping @MainActor @Sendable ([BlockGenModel]) -> Void
    ) async throws -> [BlockGenModel] {
        return try await provider.extractWithProgress(
            from: pdfDocument,
            onPartialBlocks: onProgress
        )
    }

    /// Extracts blocks from a PDF document
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Extracted blocks
    @MainActor
    public func extract(from pdfDocument: PDFDocument) async throws -> [BlockGenModel] {
        return try await provider.extract(from: pdfDocument)
    }
}

#endif
