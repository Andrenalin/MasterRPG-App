// @copyright André Trettin

import Foundation
import FoundationModels

/// Analyzes a character sheet (values, background, portrait description and tags) and extracts
/// the name, a description and the tag parts with on-device AI.
///
/// A character that already has a name keeps it: the name is passed to the model so the
/// description can use it, and it replaces whatever name the model writes.
struct CharacterSummaryAnalyzer: Sendable {

    private let maxCharacters: Int
    private let instructions: String

    init(maxCharacters: Int = 7000, instructions: String? = nil) {
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    /// - Parameter characterName: the character's name, empty when it has none.
    func analyzeCharacter(
        sheetText: String,
        characterName: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String = "English"
    ) async throws -> CharacterSummaryAnalysis {
        guard SystemLanguageModel.default.availability == .available else {
            throw PdfSummaryAnalysisError.modelUnavailable
        }

        let existingName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = FoundationModelInputLimiter.limitedText(sheetText, maxCharacters: maxCharacters)

        let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language.\n" + UntrustedPromptText.instruction
        let session = LanguageModelSession(instructions: activeInstructions)
        session.prewarm()

        let stream = session.streamResponse(
            to: buildPrompt(with: truncated, existingName: existingName, outputLanguage: outputLanguage),
            generating: CharacterSummaryAnalysis.self
        )

        var latestContent: CharacterSummaryAnalysis.PartiallyGenerated?

        do {
            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                await resultModel.setAnalysisProgress(TableSummaryAnalysisProgress(content, existingName: existingName))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PdfSummaryAnalysisError {
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            throw PdfSummaryAnalysisError.generationFailed(FoundationModelsErrorHandler.message(for: error, subject: .character))
        } catch {
            throw PdfSummaryAnalysisError.generationFailed(error.localizedDescription)
        }

        guard let partial = latestContent,
              let name = partial.name,
              let description = partial.description,
              let race = partial.race,
              let occupation = partial.occupation,
              let traits = partial.traits else {
            throw PdfSummaryAnalysisError.generationFailed(
                String(
                    localized: "Streaming completed but no content was received.",
                    bundle: .module
                )
            )
        }

        return CharacterSummaryAnalysis(
            name: existingName.isEmpty ? name : existingName,
            description: description,
            race: race,
            occupation: occupation,
            sex: partial.sex ?? "",
            traits: traits
        )
    }

    private func buildPrompt(with text: String, existingName: String, outputLanguage: String) -> String {
        let nameRule = existingName.isEmpty
            ? "The character has no name yet: invent a personal name that fits the race, sex and world, never a description of race or occupation."
            : "The character is named \"\(existingName)\". Use exactly this name."
        return """
        Analyze this role-playing game character sheet and extract the name, a description and the tag parts.
        Output language: \(outputLanguage)

        Character sheet:
        \(UntrustedPromptText.fenced(text))

        \(nameRule)
        Provide in \(outputLanguage):
        - The name
        - A description of one or two sentences about who the character is
        - The race, the class or occupation, and the sex only when the sheet or the portrait shows it
        - Two traits that are special about this character, based on the highest values and the background
        """
    }

    private static let defaultInstructions = """
    Analyze the character sheet of a tabletop role-playing game: a player character, a \
    non-player character or a monster. The sheet lists the character's values (attributes, \
    skills, equipment, background) and can end with the description and tags of the \
    character's portrait.
    Extract the name, a description, the race, the class or occupation, the sex and two traits.
    The description has one or two sentences about the character: race, class or occupation and \
    what makes them special. It is about the character, never about "entries", "values", "a \
    sheet" or "a table".
    The race keeps a name that only exists in the game's own world unchanged (Fjordzwerg, \
    Kaiter). A common race is always written in the output language, also when the sheet is in \
    another language. When the sheet names no race, use Human. The description names the race too.
    The occupation is the class or occupation the sheet names, written in the output language \
    with its closest meaning. Only a monster without one gets its role in a fight.
    The sex is Male or Female in the output language, only when something shows it: a pronoun, \
    a gendered word for a person, a clearly male or female first name, or the portrait. A \
    monster, creature or stat block without such a word has no sex: leave it empty. Never guess.
    The two traits say what is special about this character and are read from the sheet, not \
    imagined: the values that are clearly higher than the others, the background, the weapon or \
    the special abilities. Name what they show in your own words, in the output language. A low \
    or average value is no trait. A trait has 1 to 3 words, does not repeat the race, occupation \
    or sex, has no label and is never a generic word such as "Character", "Stats" or "Attributes".
    Never use the words \(GeneratedTagRules.bannedWordsText).
    Be precise and factual.
    """
}

extension CharacterSummaryAnalyzer: TextSummaryAnalyzing {
    func analyze(
        entriesText: String,
        itemName: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String
    ) async throws -> TableSummaryAnalysis {
        try await analyzeCharacter(
            sheetText: entriesText,
            characterName: itemName,
            resultModel: resultModel,
            outputLanguage: outputLanguage
        ).summary
    }
}
