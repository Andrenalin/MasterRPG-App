// @copyright André Trettin

#if !os(tvOS)
import Foundation
import FoundationModels

/// The availability check and error mapping the summary analyzers share (PDF, table, character),
/// so a fix lands in one place. See CODE_AUDIT_29 §9.1.
enum AnalyzerRunner {
    /// Throws `modelUnavailable` unless the on-device model can run.
    static func requireModel() throws {
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfSummaryAnalysisError.modelUnavailable
        }
    }

    /// Runs `body`, keeps a cancellation a cancellation and turns every model error into one
    /// `generationFailed` message for `subject`.
    static func run<Result>(
        subject: FoundationModelsErrorHandler.Subject,
        _ body: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await body()
        } catch is CancellationError {
            // A cancelled analysis stays a cancellation; it is not a "generation failed" message.
            // See CODE_AUDIT_26 §5.114.
            throw CancellationError()
        } catch let error as PdfSummaryAnalysisError {
            throw error
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(FoundationModelsErrorHandler.message(for: error, subject: subject))
        }
    }
}

#endif
