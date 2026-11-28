// @copyright André Trettin

import CoreRPG
import Foundation
import FoundationModels
import os.log

/// Turns the errors a `LanguageModelSession` throws into one localized sentence for the user.
///
/// iOS 27 throws `LanguageModelError`; the deprecated `LanguageModelSession.GenerationError` is
/// still recognised. Both map to one `Kind`, so every catch site shows the same messages. The
/// framework's `debugDescription` is logged, never shown: it is internal and not localized.
/// See CODE_AUDIT_29 §4.1, §6.5.
struct FoundationModelsErrorHandler: Sendable {
    /// What an analysis, extraction or generation ran on. Only the messages that name the subject
    /// differ; every other case shares one wording. See CODE_AUDIT_26 §9.4.
    enum Subject: Sendable {
        case pdfAnalysis
        case pdfExtraction
        case table
        case character
        case map
        case adventure
        /// A generator chat, block generation or the Run Generator intent.
        case generation
    }

    /// The model failures both error types describe.
    enum Kind: Sendable, Equatable {
        case contextSizeExceeded
        case assetsUnavailable
        case guardrailViolation
        case decodingFailure
        case unsupportedGuide
        case unsupportedLanguageOrLocale
        case unsupportedCapability
        case rateLimited
        case concurrentRequests
        case refusal
        case timeout
        case unknown

        /// `nil` for an error that is not a model error.
        init?(_ error: any Error) {
            #if !os(tvOS)
            if #available(iOS 27, macOS 27, visionOS 27, *), let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: self = .contextSizeExceeded
                case .rateLimited: self = .rateLimited
                case .guardrailViolation: self = .guardrailViolation
                case .refusal: self = .refusal
                case .unsupportedCapability, .unsupportedTranscriptContent: self = .unsupportedCapability
                case .unsupportedGenerationGuide: self = .unsupportedGuide
                case .unsupportedLanguageOrLocale: self = .unsupportedLanguageOrLocale
                case .timeout: self = .timeout
                @unknown default: self = .unknown
                }
                return
            }
            #endif
            guard let error = error as? LanguageModelSession.GenerationError else { return nil }
            switch error {
            case .exceededContextWindowSize: self = .contextSizeExceeded
            case .assetsUnavailable: self = .assetsUnavailable
            case .guardrailViolation: self = .guardrailViolation
            case .decodingFailure: self = .decodingFailure
            case .unsupportedGuide: self = .unsupportedGuide
            case .unsupportedLanguageOrLocale: self = .unsupportedLanguageOrLocale
            case .rateLimited: self = .rateLimited
            case .concurrentRequests: self = .concurrentRequests
            case .refusal: self = .refusal
            @unknown default: self = .unknown
            }
        }
    }

    /// The message for any error a model session threw while working on `subject`.
    static func message(for error: any Error, subject: Subject) -> String {
        if let kind = Kind(error) {
            Logger.generatorRPG.error("Foundation Models error: \(String(describing: error), privacy: .private)")
            return message(for: kind, subject: subject) ?? String(localized: "Unexpected error: \(error.localizedDescription)", bundle: .module)
        }
        if let toolCallError = error as? LanguageModelSession.ToolCallError {
            return handleToolCallError(toolCallError)
        }
        if let coreError = error as? FoundationModelCoreError {
            return coreError.localizedDescription
        }
        return String(localized: "Unexpected error: \(error.localizedDescription)", bundle: .module)
    }

    /// The message for a generator request (chat, blocks, intent).
    static func handleError(_ error: any Error) -> String {
        message(for: error, subject: .generation)
    }

    /// `nil` for `.unknown`, which shows the error's own description.
    static func message(for kind: Kind, subject: Subject) -> String? {
        switch kind {
        case .contextSizeExceeded:
            switch subject {
            case .pdfAnalysis, .pdfExtraction:
                return String(localized: "PDF content is too large for processing. Try a smaller document or fewer pages.", bundle: .module)
            case .table:
                return String(localized: "Table content is too large. Try a table with fewer entries.", bundle: .module)
            case .character:
                return String(localized: "The character sheet is too large. Try a character with fewer values.", bundle: .module)
            case .map:
                return String(localized: "The map has too much text. Try a map with fewer rooms.", bundle: .module)
            case .adventure:
                return String(localized: "The adventure has too much text. Try an adventure with fewer entries.", bundle: .module)
            case .generation:
                return String(localized: "The request is too long for Apple Intelligence. Try a shorter one.", bundle: .module)
            }
        case .guardrailViolation:
            switch subject {
            case .pdfAnalysis:
                return String(localized: "Content policy prevented analysis. The PDF may contain inappropriate content.", bundle: .module)
            case .pdfExtraction:
                return String(localized: "Content policy prevented extraction. The PDF may contain inappropriate content.", bundle: .module)
            case .table, .character, .map, .adventure:
                return String(localized: "Content policy prevented analysis.", bundle: .module)
            case .generation:
                return String(localized: "Content policy prevented a response.", bundle: .module)
            }
        case .unsupportedLanguageOrLocale:
            switch subject {
            case .pdfAnalysis, .pdfExtraction:
                return String(localized: "The PDF language is not supported by Apple Intelligence.", bundle: .module)
            case .table:
                return String(localized: "The table language is not supported by Apple Intelligence.", bundle: .module)
            case .character:
                return String(localized: "The character's language is not supported by Apple Intelligence.", bundle: .module)
            case .map:
                return String(localized: "The map's language is not supported by Apple Intelligence.", bundle: .module)
            case .adventure:
                return String(localized: "The adventure's language is not supported by Apple Intelligence.", bundle: .module)
            case .generation:
                return String(localized: "The language is not supported by Apple Intelligence.", bundle: .module)
            }
        case .assetsUnavailable:
            return String(localized: "The Apple Intelligence model is not downloaded yet. Try again later.", bundle: .module)
        case .decodingFailure:
            return String(localized: "The response could not be read. Try again.", bundle: .module)
        case .unsupportedGuide:
            return String(localized: "The request uses a format Apple Intelligence does not support.", bundle: .module)
        case .unsupportedCapability:
            return String(localized: "The model on this device does not support this request.", bundle: .module)
        case .rateLimited:
            return String(localized: "Apple Intelligence is busy. Try again in a moment.", bundle: .module)
        case .concurrentRequests:
            return String(localized: "Too many requests at once. Please wait.", bundle: .module)
        case .refusal:
            return String(localized: "Apple Intelligence declined to respond.", bundle: .module)
        case .timeout:
            return String(localized: "Apple Intelligence took too long. Try again.", bundle: .module)
        case .unknown:
            return nil
        }
    }

    static func handleToolCallError(_ error: LanguageModelSession.ToolCallError) -> String {
        Logger.generatorRPG.error("Foundation Models tool call error: \(String(describing: error.underlyingError), privacy: .private)")
        return String(
            localized: "Tool '\(error.tool.name)' failed: \(error.underlyingError.localizedDescription)",
            bundle: .module
        )
    }
}
