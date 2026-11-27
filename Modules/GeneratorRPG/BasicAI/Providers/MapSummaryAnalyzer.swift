// @copyright André Trettin

import Foundation
import FoundationModels

/// Analyzes a map (its rooms and the description and tags of its photo) and extracts a title, a
/// description, the kind of place and tags with on-device AI. The kind is the first tag, written
/// in the output language (`MapPlaceKind.name(in:)`); "Map" and the like are removed from the title and
/// the tags in code, because the model keeps writing "Dungeon Map" whatever the prompt says.
struct MapSummaryAnalyzer: Sendable {

    private let maxCharacters: Int
    private let instructions: String

    init(maxCharacters: Int = 7000, instructions: String? = nil) {
        self.maxCharacters = maxCharacters
        self.instructions = instructions ?? Self.defaultInstructions
    }

    func analyzeMap(
        mapText: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String = "English"
    ) async throws -> TableSummaryAnalysis {
        try AnalyzerRunner.requireModel()

        let truncated = FoundationModelInputLimiter.limitedText(mapText, maxCharacters: maxCharacters)

        let activeInstructions = instructions + "\nIMPORTANT: All output must be written in \(outputLanguage), regardless of the input language.\n" + UntrustedPromptText.instruction
        let session = LanguageModelSession(instructions: activeInstructions)
        session.prewarm()

        let stream = session.streamResponse(
            to: buildPrompt(with: truncated, outputLanguage: outputLanguage),
            generating: MapSummaryGeneration.self
        )

        var latestContent: MapSummaryGeneration.PartiallyGenerated?

        try await AnalyzerRunner.run(subject: .map) {
            for try await snapshot in stream {
                let content = snapshot.content
                latestContent = content
                await resultModel.setAnalysisProgress(TableSummaryAnalysisProgress(content, outputLanguage: outputLanguage))
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

        let finalTitle = MapSummaryGeneration.cleanedTitle(title, kind: kind, outputLanguage: outputLanguage)
        return TableSummaryAnalysis(
            title: finalTitle,
            description: description,
            tags: MapSummaryGeneration.tags(kind: kind, contentTags: partial.tags, title: finalTitle, outputLanguage: outputLanguage)
        )
    }

    private func buildPrompt(with text: String, outputLanguage: String) -> String {
        """
        Analyze this role-playing game map and extract a title, a description, the kind of place and tags.
        Output language: \(outputLanguage)

        Map:
        \(UntrustedPromptText.fenced(text))

        Provide in \(outputLanguage), in this order:
        - A title of 2 to 6 words that names the place, without the word map
        - A description of one or two sentences about the place: what kind of place it is and what is special about it
        - The kind of place, decided by the map photo's description and tags first, then by the rooms
        - \(MapSummaryGeneration.contentTagRange.lowerBound) to \(MapSummaryGeneration.contentTagRange.upperBound) tags about what is special in this place, not the kind of place
        """
    }

    private static let defaultInstructions = """
    Analyze the map of a tabletop role-playing game. The text has the map's name when it has one, \
    the description and tags of the map's photo when there are any, and the rooms or locations \
    marked on the map. The photo's description and tags say best what kind of place the map \
    shows; the rooms say what is in it.
    Extract, in this order, a title, a description, the kind of place and tags.
    The title has 2 to 6 words and names the place: the map's own name when the text gives one, \
    otherwise what and where the place is, in the output language. It is no sentence, has no final period and no label \
    before it. It never contains the words "Map", "Plan", "Layout" or "Rooms" (or their \
    translations): write "Blackwater Keep", never "Blackwater Keep Map"; "Sunken Crypt", never \
    "Crypt Map".
    The description has one or two sentences about the place itself: what kind of place it is, \
    where it is and what is special about it. It never calls the place a map, a table, entries \
    or a list.
    The kind of place is one of these, the one that fits the place as a whole best:
    \(MapPlaceKind.instructionList)
    Decide the kind by the photo's description and tags first. A castle or keep is a fortress \
    even when it has dungeon cells; an inn or a manor is a building; a grove is a forest; \
    natural caves are a cave, an underground complex built by people is a dungeon; a ship with \
    a reactor, an airlock or a cockpit, or in a science-fiction setting, is a spaceship.
    Tags are \(MapSummaryGeneration.contentTagRange.lowerBound) to \
    \(MapSummaryGeneration.contentTagRange.upperBound) short keywords that tell this place apart \
    from other places of the same kind: its specific places, creatures, people, factions, items \
    and themes, and the genre when the photo names one. A tag never repeats the kind of place \
    and never contains the words "Map", "Plan", "Layout" or "Rooms". Photo tags, room names and \
    words in another language are translated into the output language, never copied: from German \
    to English, "Wald" is "Forest" and "Elfen" is "Elves". \
    \(GeneratedTagRules.rules(extraGenericTags: MapSummaryGeneration.genericTags))
    Never use the words \(GeneratedTagRules.bannedWordsText) in the description either.
    Be precise and factual.
    """
}

extension MapSummaryAnalyzer: TextSummaryAnalyzing {
    func analyze(
        entriesText: String,
        itemName _: String,
        resultModel: TableSummaryAnalyzerResultModel,
        outputLanguage: String
    ) async throws -> TableSummaryAnalysis {
        try await analyzeMap(mapText: entriesText, resultModel: resultModel, outputLanguage: outputLanguage)
    }
}
