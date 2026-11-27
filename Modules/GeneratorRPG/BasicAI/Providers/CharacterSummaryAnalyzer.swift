// @copyright André Trettin

import Foundation
import FoundationModels

/// Analyzes a character sheet (values, background, portrait description and tags) and extracts
/// the name, a description and the tag parts with on-device AI.
///
/// A character that already has a name keeps it: the name is passed to the model so the
/// description can use it, and it replaces whatever name the model writes. The model generates
/// `CharacterSummaryGeneration`; the player's name is kept only when it is a name of the sheet
/// (`verifiedPlayerName`).
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
        try AnalyzerRunner.requireModel()

        let existingName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = FoundationModelInputLimiter.limitedText(sheetText, maxCharacters: maxCharacters)

        let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language.\n" + UntrustedPromptText.instruction
        let session = LanguageModelSession(instructions: activeInstructions)
        session.prewarm()

        let stream = session.streamResponse(
            to: buildPrompt(with: truncated, existingName: existingName, outputLanguage: outputLanguage),
            generating: CharacterSummaryGeneration.self
        )

        var latestContent: CharacterSummaryGeneration.PartiallyGenerated?

        try await AnalyzerRunner.run(subject: .character) {
            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                await resultModel.setAnalysisProgress(TableSummaryAnalysisProgress(content, existingName: existingName))
            }
        }

        guard let partial = latestContent,
              let name = partial.name,
              let description = partial.description,
              let race = partial.race else {
            throw PdfSummaryAnalysisError.generationFailed(
                String(
                    localized: "Streaming completed but no content was received.",
                    bundle: .module
                )
            )
        }

        let finalName = existingName.isEmpty ? name : existingName
        // The existing name is part of the sheet text too; a player's name must be another name.
        let playerName = CharacterSummaryGeneration.verifiedPlayerName(partial.playerName, in: truncated, characterName: finalName)
        return CharacterSummaryAnalysis(
            name: finalName,
            description: description,
            race: race,
            occupation: partial.occupation ?? "",
            traits: (partial.traits ?? []).prefix(2).map(CharacterSummaryGeneration.cleanedTrait),
            playerName: playerName
        )
    }

    /// `name` as one line of at most 80 characters, without quotes.
    static func promptSafeName(_ name: String) -> String {
        let line = name
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .filter { !"\"“”„«»".contains($0) }
        return String(line.prefix(80))
    }

    private func buildPrompt(with text: String, existingName: String, outputLanguage: String) -> String {
        let nameRule = existingName.isEmpty
            ? "The character has no name yet: invent a personal name that fits the race and world, never a description of race or occupation."
            // The name can come from an import or a peer: it goes into the fence, never into the
            // instructions, and it is one short line. See CODE_AUDIT_29 §6.4.
            : "The character already has the name given in this block; use exactly this name:\n\(UntrustedPromptText.fenced(Self.promptSafeName(existingName)))"
        return """
        Analyze this role-playing game character sheet and extract the name, a description and the tag parts.
        Output language: \(outputLanguage)

        Character sheet:
        \(UntrustedPromptText.fenced(text))
        \(Self.glossaryText(for: text, outputLanguage: outputLanguage))
        \(nameRule)
        Provide in \(outputLanguage), in this order:
        - The name
        - A description of one or two sentences about who the character is, naming the race and the class or occupation
        - The race: a people, the animal's name for an animal, or the monster's own name
        - The class, occupation or role, only when the sheet names one, otherwise nothing
        - The player's name, only when the sheet names the player, otherwise nothing
        - Up to two traits of 1 to 3 words that are special about this character, based on the highest values and the background
        """
    }

    /// The glossary lines for the German class and race words on the sheet, with an empty line
    /// before and after; an empty line alone when there are none.
    static func glossaryText(for text: String, outputLanguage: String) -> String {
        let hints = CharacterTermGlossary.hints(in: text, outputLanguage: outputLanguage)
        guard !hints.isEmpty else { return "" }
        return "\nWords on this sheet and their game terms, to write in \(outputLanguage):\n"
            + hints.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }

    private static let defaultInstructions = """
    Analyze the character sheet of a tabletop role-playing game: a player character, a \
    non-player character, an animal or a monster. The sheet lists the character's values \
    (attributes, skills, equipment, background) and can end with the description and tags of \
    the character's portrait.
    Extract, in this order, the name, a description, the race, the class or occupation, the \
    player's name and up to two traits.
    The race is always given: the character's people, the animal's name for an animal, or the \
    monster's own name for a monster. The race keeps a name that only exists in the game's own world unchanged \
    (Fjordzwerg, Kaiter). A common race is always written in the output language, also when the \
    sheet is in another language. When the sheet names no race for a person, use Human.
    The class or occupation is only given when the sheet or the portrait names a class, an \
    occupation or a role, written in the output language with its closest meaning; a game class \
    is written as the game term. When nothing names one, leave it empty. Never guess.
    The player's name is the real person who plays the character, only when a value of the sheet \
    names the player. Copy it exactly. Never use the character's own name for it.
    The traits say what is special about this character and are read from the sheet, not \
    imagined: the values that are clearly higher than the others, the background, the weapon or \
    the special abilities. Give two, one or none: none is better than a weak trait. Name what \
    they show in your own words, in the output language. A low or average value is no trait. A \
    trait has 1 to 3 words and is no sentence, does not repeat the race or the class or \
    occupation, has no label and is never a generic word such as "Character", "Stats" or \
    "Attributes".
    The description has one or two sentences about the character: it names the race and the \
    class or occupation and says what makes them special. It is about the character, never \
    about "entries", "values", "a sheet" or "a table".
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
