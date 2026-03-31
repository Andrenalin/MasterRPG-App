// @copyright André Trettin

#if !os(tvOS)

import Foundation
import GeneratorRPG
import FoundationModels
import Observation

#if canImport(PDFKit)
import PDFKit
#endif

/// Observable model for PDF summary analysis UI state
@MainActor
@Observable
public final class PdfSummaryAnalysisModel {

    // MARK: - Published State

    public var isAnalyzing: Bool = false
    public var analysisProgress: PdfSummaryAnalysis.PartiallyGenerated?
    public var lastError: String?
    public var isModelAvailable: Bool = true

    // MARK: - Use Case

    private let useCase: AnalyzePdfSummaryUseCase

    // MARK: - Initialization

    public init(useCase: AnalyzePdfSummaryUseCase = AnalyzePdfSummaryUseCase()) {
        self.useCase = useCase
        checkModelAvailability()
    }

    // MARK: - Actions

    /// Analyzes PDF with streaming progress updates
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Final summary analysis, or nil if analysis fails
    public func analyzeWithProgress(from pdfDocument: PDFDocument) async -> PdfSummaryAnalysis? {
        guard isModelAvailable else {
            lastError = "Apple Intelligence is not available on this device"
            return nil
        }

        isAnalyzing = true
        analysisProgress = nil
        lastError = nil

        defer {
            isAnalyzing = false
            analysisProgress = nil
        }

        do {
            let content = try await useCase.analyzeWithProgress(from: pdfDocument) { [weak self] partial in
                self?.analysisProgress = partial
            }
            return content
        } catch {
            lastError = error.localizedDescription
            return nil
        }
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
