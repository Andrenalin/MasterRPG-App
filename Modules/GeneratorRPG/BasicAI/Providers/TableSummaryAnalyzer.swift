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

        let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language."
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
                await MainActor.run {
                    resultModel.analysisProgress = progress
                }
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfSummaryAnalysisError.generationFailed(handleGenerationError(error))
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(error.localizedDescription)
        }

        guard let partial = latestContent,
              let title = partial.title,
              let description = partial.description,
              let tags = partial.tags else {
            throw PdfSummaryAnalysisError.generationFailed("Streaming completed but no content received")
        }

        return TableSummaryAnalysis(title: title, description: description, tags: tags)
    }

    private func buildPrompt(with text: String, outputLanguage: String) -> String {
        """
        Analyze these RPG table entries and extract structured metadata.
        Output language: \(outputLanguage)

        Table entries:
        \(text)

        Provide in \(outputLanguage):
        - A clear title for this table
        - A 1–2 sentence description of its purpose and content
        - 2–8 relevant RPG tags (genre, setting, mechanics, use case, etc.)
        """
    }

    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            return "Table content is too large. Try a table with fewer entries."
        case .guardrailViolation:
            return "Content policy prevented analysis."
        case .unsupportedLanguageOrLocale:
            return "The table language is not supported by Apple Intelligence."
        case .assetsUnavailable(let reason):
            return "Model assets unavailable: \(reason). Ensure Apple Intelligence is downloaded."
        case .unsupportedGuide(let guide):
            return "Schema contains unsupported constraint: \(guide)."
        case .decodingFailure(let reason):
            return "Failed to decode result: \(reason)."
        case .rateLimited(let retryAfter):
            return "Rate limit exceeded. Try again in \(retryAfter) seconds."
        case .concurrentRequests(let maxCount):
            return "Too many concurrent requests (max \(maxCount)). Please wait."
        case .refusal(let reason, let category):
            return "Analysis refused: \(reason) (category: \(category))."
        @unknown default:
            return "Unexpected error: \(error.localizedDescription)"
        }
    }

    private static let defaultInstructions = """
    Analyze RPG table entries (random tables, encounter tables, loot tables, etc.).
    Extract a clear title, concise description, and relevant tags.
    Be precise and use the same language as the entries.
    """
}
