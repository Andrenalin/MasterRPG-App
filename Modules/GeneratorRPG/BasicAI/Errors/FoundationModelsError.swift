// @copyright André Trettin

import Foundation
import FoundationModels

/// Custom error types for Foundation Models operations
nonisolated enum FoundationModelsError: LocalizedError, Sendable {
    case sessionCreationFailed
    case responseGenerationFailed(String)
    case toolCallFailed(String)
    case streamingFailed(String)
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return String(localized: "Failed to create language model session", bundle: .module)
        case .responseGenerationFailed(let message):
            return String(localized: "Response generation failed: \(message)", bundle: .module)
        case .toolCallFailed(let message):
            return String(localized: "Tool call failed: \(message)", bundle: .module)
        case .streamingFailed(let message):
            return String(localized: "Streaming failed: \(message)", bundle: .module)
        case .modelUnavailable(let message):
            return String(localized: "Model unavailable: \(message)", bundle: .module)
        }
    }
}

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
        } else if let customError = error as? FoundationModelsError {
            return customError.localizedDescription
        } else {
            return String(localized: "Unexpected error: \(error.localizedDescription)", bundle: .module)
        }
    }
}
