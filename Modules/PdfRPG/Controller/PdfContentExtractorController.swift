// @copyright André Trettin

#if !os(tvOS)

import Foundation
import GeneratorRPG
import FoundationModels
import Observation

#if canImport(PDFKit)
import PDFKit
#endif

/// Controller for PDF content extraction in the PdfRPG module
@MainActor
@Observable
public final class PdfContentExtractorController {

    // MARK: - Published Properties

    public private(set) var isExtracting: Bool = false
    public private(set) var extractionProgress: PdfExtractedContent.PartiallyGenerated?
    public private(set) var lastError: String?
    public private(set) var isModelAvailable: Bool = true

    // MARK: - Private Properties

    private let useCase: ExtractPdfContentUseCase

    // MARK: - Initialization

    public init(useCase: ExtractPdfContentUseCase = ExtractPdfContentUseCase()) {
        self.useCase = useCase
        checkModelAvailability()
    }

    // MARK: - Public Methods

    /// Extracts content from a PDF document
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Structured extracted content, or nil if extraction fails
    public func extract(from pdfDocument: PDFDocument) async -> PdfExtractedContent? {
        guard isModelAvailable else {
            lastError = "Apple Intelligence is not available on this device"
            return nil
        }

        isExtracting = true
        extractionProgress = nil
        lastError = nil

        defer { isExtracting = false }

        do {
            let content = try await useCase.extract(from: pdfDocument)
            return content
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Extracts content with streaming progress updates
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Final extracted content, or nil if extraction fails
    public func extractWithProgress(from pdfDocument: PDFDocument) async -> PdfExtractedContent? {
        guard isModelAvailable else {
            lastError = "Apple Intelligence is not available on this device"
            return nil
        }

        isExtracting = true
        extractionProgress = nil
        lastError = nil

        defer {
            isExtracting = false
            extractionProgress = nil
        }

        do {
            let content = try await useCase.extractWithProgress(from: pdfDocument) { [weak self] partial in
                self?.extractionProgress = partial
            }
            return content
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Extracts content from a PDF file URL
    /// - Parameter url: URL to the PDF file
    /// - Returns: Structured extracted content, or nil if extraction fails
    public func extract(from url: URL) async -> PdfExtractedContent? {
        guard let pdfDocument = PDFDocument(url: url) else {
            lastError = "Failed to load PDF from URL"
            return nil
        }
        return await extract(from: pdfDocument)
    }

    /// Checks if the Foundation Models are available
    public func checkModelAvailability() {
        isModelAvailable = SystemLanguageModel.default.availability == .available
    }

    /// Clears the last error message
    public func clearError() {
        lastError = nil
    }
}

#endif
