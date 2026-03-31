// @copyright André Trettin

#if !os(tvOS)

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Request

public struct PdfSummaryAnalysisRequest: CapabilityRequest {
    public let pdfData: Data?
    public let pdfUrl: URL?
    public let useStreaming: Bool

    public init(pdfData: Data? = nil, pdfUrl: URL? = nil, useStreaming: Bool = false) {
        self.pdfData = pdfData
        self.pdfUrl = pdfUrl
        self.useStreaming = useStreaming
    }
}

// MARK: - Use Case

/// Use case for analyzing and summarizing PDF documents
public struct AnalyzePdfSummaryUseCase {

    public static let descriptor = CapabilityDescriptor(
        id: "foundation-models.analyze-pdf-summary",
        displayName: "PDF Summary Analysis",
        summary: "Analyzes and summarizes RPG PDF documents using Foundation Models."
    )

    private let provider: any PdfSummaryAnalyzing

    public init(provider: any PdfSummaryAnalyzing) {
        self.provider = provider
    }

    @MainActor
    public init() {
        self.provider = PdfSummaryAnalyzer()
    }

    // MARK: - Convenience Methods

    /// Analyzes PDF document with streaming progress
    /// - Parameters:
    ///   - pdfDocument: The PDF to analyze
    ///   - onProgress: Callback for incremental updates
    /// - Returns: Summary analysis
    @MainActor
    public func analyzeWithProgress(
        from pdfDocument: PDFDocument,
        onProgress: @escaping @MainActor @Sendable (PdfSummaryAnalysis.PartiallyGenerated) -> Void
    ) async throws -> PdfSummaryAnalysis {
        return try await provider.analyzeWithProgress(
            from: pdfDocument,
            onPartialContent: onProgress
        )
    }
}

#endif
