// @copyright André Trettin

import Foundation
import FoundationModels

/// Analyzes table entry text and extracts structured metadata using on-device AI.
struct TableSummaryAnalyzer {

    private let maxCharacters: Int
    private let instructions: String

    init(maxCharacters: Int = 7000, instructions: String? = nil) {
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    func analyze(entriesText: String, resultModel: TableSummaryAnalyzerResultModel, outputLanguage: String = "English") async throws -> TableSummaryAnalysis {
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfSummaryAnalysisError.modelUnavailable
        }

        let truncated = FoundationModelInputLimiter.limitedText(entriesText, maxCharacters: maxCharacters)

        let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language.\n" + UntrustedPromptText.instruction
        let session = LanguageModelSession(instructions: activeInstructions)
        session.prewarm()

        let stream = session.streamResponse(
            to: buildPrompt(with: truncated, outputLanguage: outputLanguage),
            generating: TableSummaryAnalysis.self
        )

        var latestContent: TableSummaryAnalysis.PartiallyGenerated?

        do {
            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                let progress = TableSummaryAnalysisProgress(content)
                await resultModel.setAnalysisProgress(progress)
            }
        } catch is CancellationError {
            // A cancelled analysis stays a cancellation; it is not a "generation failed" message.
            // See CODE_AUDIT_26 §5.114.
            throw CancellationError()
        } catch let error as PdfSummaryAnalysisError {
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfSummaryAnalysisError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(error.localizedDescription)
        }

        guard let partial = latestContent,
              let title = partial.title,
              let description = partial.description,
              let tags = partial.tags else {
            throw PdfSummaryAnalysisError.generationFailed(
                String(
                    localized: "Streaming completed but no content was received.",
                    bundle: .module
                )
            )
        }

        return TableSummaryAnalysis(title: title, description: description, tags: tags)
    }

    private func buildPrompt(with text: String, outputLanguage: String) -> String {
        """
        Analyze these RPG table entries and extract structured metadata.
        Output language: \(outputLanguage)

        Table entries:
        \(UntrustedPromptText.fenced(text))

        Provide in \(outputLanguage):
        - A clear title for this table
        - A 1–2 sentence description of its purpose and content
        - 2–8 relevant RPG tags (genre, setting, mechanics, use case, etc.)
        """
    }

    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return String(
                localized: "Table content is too large. Try a table with fewer entries.",
                bundle: .module
            )
        case .guardrailViolation:
            return String(localized: "Content policy prevented analysis.", bundle: .module)
        case .unsupportedLanguageOrLocale:
            return String(
                localized: "The table language is not supported by Apple Intelligence.",
                bundle: .module
            )
        case .assetsUnavailable(let reason):
            return String(
                localized: "Model assets unavailable: \(String(describing: reason)). Ensure Apple Intelligence is downloaded.",
                bundle: .module
            )
        case .unsupportedGuide(let guide):
            return String(
                localized: "Schema contains unsupported constraint: \(String(describing: guide)).",
                bundle: .module
            )
        case .decodingFailure(let reason):
            return String(
                localized: "Failed to decode result: \(String(describing: reason)).",
                bundle: .module
            )
        case .rateLimited(let retryAfter):
            return String(
                localized: "Rate limit exceeded. Try again in \(String(describing: retryAfter)) seconds.",
                bundle: .module
            )
        case .concurrentRequests(let maxCount):
            return String(
                localized: "Too many concurrent requests (max \(String(describing: maxCount))). Please wait.",
                bundle: .module
            )
        case .refusal(let reason, let category):
            return String(
                localized: "Analysis refused: \(String(describing: reason)) (category: \(String(describing: category))).",
                bundle: .module
            )
        @unknown default:
            return String(localized: "Unexpected error: \(error.localizedDescription)", bundle: .module)
        }
    }

    private static let defaultInstructions = """
    Analyze RPG table entries (random tables, encounter tables, loot tables, etc.).
    Extract a clear title, concise description, and relevant tags.
    Be precise.
    """
}
