// @copyright André Trettin

import CoreRPG
import Foundation
import FoundationModels

/// Analyzes an adventure (its scenes and chapters) and extracts a title, a short summary, the type
/// of adventure and tags with on-device AI. The tags are, in this order: the level band ("1-4") and
/// the number of player characters ("3-5 PC"), both read from the text in code
/// (`AdventurePartyFacts`) and left out when the text names neither, then the type
/// (`AdventurePlotKind.name(in:)`), then the model's tags about the adventure.
struct AdventureSummaryAnalyzer: Sendable {

    private let maxCharacters: Int
    private let instructions: String

    init(maxCharacters: Int = 7000, instructions: String? = nil) {
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    func analyzeAdventure(
        adventureText: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String = "English"
    ) async throws -> TableSummaryAnalysis {
        try AnalyzerRunner.requireModel()

        // The whole text, not the truncated one: the level is often named only once.
        let facts = AdventurePartyFacts(text: adventureText)
        let truncated = FoundationModelInputLimiter.limitedText(adventureText, maxCharacters: maxCharacters)

        let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language.\n" + UntrustedPromptText.instruction
        let session = LanguageModelSession(instructions: activeInstructions)
        session.prewarm()

        let stream = session.streamResponse(
            to: buildPrompt(with: truncated, outputLanguage: outputLanguage),
            generating: AdventureSummaryGeneration.self
        )

        var latestContent: AdventureSummaryGeneration.PartiallyGenerated?

        try await AnalyzerRunner.run(subject: .adventure) {
            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                await resultModel.setAnalysisProgress(TableSummaryAnalysisProgress(content, facts: facts, outputLanguage: outputLanguage))
            }
        }

        guard let partial = latestContent,
              let title = partial.title,
              let description = partial.description,
              let kind = partial.kind else {
            throw PdfSummaryAnalysisError.generationFailed(
                String(
                    localized: "Streaming completed but no content was received.",
                    bundle: .module
                )
            )
        }

        let finalTitle = AdventureSummaryGeneration.cleanedTitle(title, kind: kind, outputLanguage: outputLanguage)
        return TableSummaryAnalysis(
            title: finalTitle,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: AdventureSummaryGeneration.tags(
                facts: facts,
                kind: kind,
                contentTags: partial.tags,
                title: finalTitle,
                outputLanguage: outputLanguage
            )
        )
    }

    private func buildPrompt(with text: String, outputLanguage: String) -> String {
        """
        Analyze this role-playing game adventure and extract a short summary, a title, the type of adventure and tags.
        Output language: \(outputLanguage)

        Adventure:
        \(UntrustedPromptText.fenced(text))

        Provide in \(outputLanguage), in this order:
        - A short summary in two or three sentences: what draws the heroes in, what they must do and where, and the main threat or twist
        - A title of 2 to 6 words in \(outputLanguage) that names the adventure, without the word adventure
        - The type of adventure: what the heroes mainly do
        - \(AdventureSummaryGeneration.contentTagRange.lowerBound) to \(AdventureSummaryGeneration.contentTagRange.upperBound) tags about what is special in this adventure, not its type
        """
    }

    private static let defaultInstructions = """
    Analyze an adventure of a tabletop role-playing game. The text has the adventure's name when it \
    has one and its scenes, chapters or notes.
    Extract, in this order, a short summary, a title, the type of adventure and tags.
    The title has 2 to 6 words and names the adventure: its own name when the text gives one, \
    otherwise what the adventure is about. Its common words are in the output language: words in \
    another language are translated, only proper names stay. It is no sentence, has no final \
    period and no label before it. It never contains the words "Adventure", "Scenario", "Module" \
    or "Chapter" (or their translations).
    The summary has two or three short sentences, at most 60 words, about the story: what draws the heroes in or who sends \
    them, what they must do and where, and the main threat, villain or twist. It never names the \
    character level or the number of players, and never calls the adventure a table, entries or a \
    list.
    The type of adventure is one of these, the one that fits what the heroes do in most scenes:
    \(AdventurePlotKind.instructionList)
    Decide the type by what the heroes do, not by the places they visit: a curse or haunting the \
    heroes have to uncover is an investigation even when it ends in a crypt.
    Tags are \(AdventureSummaryGeneration.contentTagRange.lowerBound) to \
    \(AdventureSummaryGeneration.contentTagRange.upperBound) short keywords that tell this \
    adventure apart from others of the same type: its important places, creatures, villains, \
    factions, items and themes, and the genre. A tag never repeats the type of adventure, never \
    names a character level or a number of characters or players, and never contains the words \
    "Adventure" or "Scenario". Places, creatures and other words in another language are \
    translated into the output language, only proper names stay as they are; a place named by a \
    common word is translated too. \
    \(GeneratedTagRules.rules(extraGenericTags: AdventureSummaryGeneration.genericTags))
    Never use the words \(GeneratedTagRules.bannedWordsText) in the summary either.
    Be precise and factual.
    """
}

extension AdventureSummaryAnalyzer: TextSummaryAnalyzing {
    func analyze(
        entriesText: String,
        itemName _: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String
    ) async throws -> TableSummaryAnalysis {
        try await analyzeAdventure(adventureText: entriesText, resultModel: resultModel, outputLanguage: outputLanguage)
    }
}
