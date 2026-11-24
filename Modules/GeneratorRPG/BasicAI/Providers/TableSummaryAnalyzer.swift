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
            throw PdfSummaryAnalysisError.generationFailed(FoundationModelsErrorHandler.message(for: error, subject: .table))
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

        return TableSummaryAnalysis(title: title, description: description, tags: GeneratedTagRules.cleaned(tags))
    }

    private func buildPrompt(with text: String, outputLanguage: String) -> String {
        """
        Analyze these RPG table entries and extract structured metadata.
        Output language: \(outputLanguage)

        Table entries:
        \(UntrustedPromptText.fenced(text))

        Provide in \(outputLanguage):
        - A title of 2 to 6 words that names what the entries are about
        - A description of one or two sentences: what the entries contain and what the table is used for
        - \(GeneratedTagRules.countText) specific tags: what kind of table it is, what the entries are about, and their specific places, creatures, items, factions or themes
        """
    }


    private static let defaultInstructions = """
    Analyze RPG table entries (random tables, encounter tables, loot tables, etc.).
    Extract a title, a description and tags.
    The title has 2 to 6 words and names what the entries are about. It is no sentence, has no \
    final period and no label before it ("Table: Forest Encounters"), and is never just "Table" \
    or "Random Table".
    The description has one or two sentences: what the entries contain and what the table is \
    used for. It does not repeat the title.
    Tags are \(GeneratedTagRules.countText) short keywords that tell this table apart from other tables: \
    what kind of table it is (rumors, encounters, loot ...), what the entries are about, and \
    their specific places, creatures, items, factions and themes. \(GeneratedTagRules.rules(extraGenericTags: TableSummaryAnalysis.genericTags))
    Never use the words \(GeneratedTagRules.bannedWordsText) in the description either.
    Be precise and factual.
    """
}
