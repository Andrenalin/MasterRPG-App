// @copyright André Trettin

import Foundation
import FoundationModels

/// Helper for handling LanguageModelSession errors
struct FoundationModelsErrorHandler: Sendable {
    static func handleGenerationError(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize(let context):
            return String(localized: "Context window exceeded: \(context.debugDescription)", bundle: .module)
        case .assetsUnavailable(let context):
            return String(localized: "Model assets unavailable: \(context.debugDescription)", bundle: .module)
        case .guardrailViolation(let context):
            return String(localized: "Content policy violation: \(context.debugDescription)", bundle: .module)
        case .decodingFailure(let context):
            return String(localized: "Failed to decode response: \(context.debugDescription)", bundle: .module)
        case .unsupportedGuide(let context):
            return String(localized: "Unsupported generation guide: \(context.debugDescription)", bundle: .module)
        case .unsupportedLanguageOrLocale(let context):
            return String(localized: "Unsupported language/locale: \(context.debugDescription)", bundle: .module)
        case .rateLimited(let context):
            return String(localized: "Rate limited: \(context.debugDescription)", bundle: .module)
        case .concurrentRequests(let context):
            return String(localized: "Too many concurrent requests: \(context.debugDescription)", bundle: .module)
            // Refusal is async throws
        case .refusal(_, let context):
            return String(localized: "Model refused to respond: \(context.debugDescription)", bundle: .module)
        @unknown default:
            return String(localized: "Unknown generation error", bundle: .module)
        }
    }

    /// What an analysis or extraction ran on. Only the three messages that name the subject differ;
    /// every other case shares one wording. See CODE_AUDIT_26 §9.4.
    enum Subject: Sendable {
        case pdfAnalysis
        case pdfExtraction
        case table
    }

    /// The message for a `GenerationError` of a PDF or table analysis/extraction.
    static func message(for error: LanguageModelSession.GenerationError, subject: Subject) -> String {
        switch error {
        case .exceededContextWindowSize:
            switch subject {
            case .pdfAnalysis, .pdfExtraction:
                return String(localized: "PDF content is too large for processing. Try a smaller document or fewer pages.", bundle: .module)
            case .table:
                return String(localized: "Table content is too large. Try a table with fewer entries.", bundle: .module)
            }
        case .guardrailViolation:
            switch subject {
            case .pdfAnalysis:
                return String(localized: "Content policy prevented analysis. The PDF may contain inappropriate content.", bundle: .module)
            case .pdfExtraction:
                return String(localized: "Content policy prevented extraction. The PDF may contain inappropriate content.", bundle: .module)
            case .table:
                return String(localized: "Content policy prevented analysis.", bundle: .module)
            }
        case .unsupportedLanguageOrLocale:
            switch subject {
            case .pdfAnalysis, .pdfExtraction:
                return String(localized: "The PDF language is not supported by Apple Intelligence.", bundle: .module)
            case .table:
                return String(localized: "The table language is not supported by Apple Intelligence.", bundle: .module)
            }
        case .assetsUnavailable(let reason):
            return String(localized: "Model assets unavailable: \(String(describing: reason)). Ensure Apple Intelligence is downloaded.", bundle: .module)
        case .unsupportedGuide(let guide):
            return String(localized: "Schema contains unsupported constraint: \(String(describing: guide)).", bundle: .module)
        case .decodingFailure(let reason):
            return String(localized: "Failed to decode result: \(String(describing: reason)).", bundle: .module)
        case .rateLimited(let retryAfter):
            return String(localized: "Rate limit exceeded. Try again in \(String(describing: retryAfter)) seconds.", bundle: .module)
        case .concurrentRequests(let maxCount):
            return String(localized: "Too many concurrent requests (max \(String(describing: maxCount))). Please wait.", bundle: .module)
        case .refusal(let reason, let category):
            return String(localized: "Analysis refused: \(String(describing: reason)) (category: \(String(describing: category))).", bundle: .module)
        @unknown default:
            return String(localized: "Unexpected error: \(error.localizedDescription)", bundle: .module)
        }
    }

    static func handleToolCallError(_ error: LanguageModelSession.ToolCallError) -> String {
        return String(
            localized: "Tool '\(error.tool.name)' failed: \(error.underlyingError.localizedDescription)",
            bundle: .module
        )
    }

    /// Consolidates error handling for LanguageModelSession operations
    static func handleError(_ error: Error) -> String {
        if let generationError = error as? LanguageModelSession.GenerationError {
            return handleGenerationError(generationError)
        } else if let toolCallError = error as? LanguageModelSession.ToolCallError {
            return handleToolCallError(toolCallError)
        } else if let coreError = error as? FoundationModelCoreError {
            return coreError.localizedDescription
        } else {
            return String(localized: "Unexpected error: \(error.localizedDescription)", bundle: .module)
        }
    }
}
