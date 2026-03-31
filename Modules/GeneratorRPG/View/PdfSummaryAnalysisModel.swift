// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels
import Observation
import PDFKit

@MainActor @Observable
final class PdfSummaryAnalysisModel {

    var isAnalyzing: Bool = false
    var analysisProgress: PdfSummaryAnalysis.PartiallyGenerated?
    var lastError: String?
    var isModelAvailable: Bool = true

    private let useCase: AnalyzePdfSummaryUseCase

    init(useCase: AnalyzePdfSummaryUseCase = AnalyzePdfSummaryUseCase()) {
        self.useCase = useCase
        checkModelAvailability()
    }

    /// Analyzes PDF with streaming progress updates
    /// - Parameter pdfDocument: The PDF to analyze
    /// - Returns: Final summary analysis, or nil if analysis fails
    func analyzeWithProgress(from pdfDocument: PDFDocument) async -> PdfSummaryAnalysis? {
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
    func checkModelAvailability() {
        isModelAvailable = SystemLanguageModel.default.availability == .available
    }

    /// Clears the last error message
    func clearError() {
        lastError = nil
    }
}

#endif
