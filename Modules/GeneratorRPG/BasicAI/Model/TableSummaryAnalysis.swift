// @copyright André Trettin

import Foundation
import FoundationModels

/// Structured extraction result for an RPG table's metadata.
/// Properties declared in generation order: title arrives first (~0.2s) for
/// progressive streaming UI before the full result is ready.
@Generable(description: "Extracted metadata from RPG table entries")
public struct TableSummaryAnalysis: Equatable, Sendable, Identifiable, Codable {

    public var id: String { title + description }

    @Guide(
        description: """
        A short title of 2 to 6 words, written in the output language, that names what the \
        entries are about, for example "Forest Encounters" or "Tavern Rumors". No sentence, no \
        period, no label such as "Table:" before it, and not just "Table" or "Random Table". \
        Do not use the word RPG.
        """
    )
    public var title: String

    @Guide(
        description: """
        One or two sentences in the output language that say what the entries contain and what \
        the table is used for. Do not repeat the title. Do not use the words \
        \(GeneratedTagRules.bannedWordsText).
        """
    )
    public var description: String

    @Guide(
        description: GeneratedTagRules.guideDescription(
            contents: """
            One tag says what kind of table this is, such as rumors, encounters or loot. One \
            says what the entries are about. The others name specific places, creatures, items, \
            factions or themes of the entries.
            """,
            extraGenericTags: TableSummaryAnalysis.genericTags
        ),
        .count(GeneratedTagRules.countRange)
    )
    public var tags: [String]

    /// Words that describe the form of a table, not its content.
    static let genericTags = ["Table", "Entries"]

    public init(title: String, description: String, tags: [String]) {
        self.title = title
        self.description = description
        self.tags = tags
    }
}
