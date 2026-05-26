// @copyright André Trettin

import Foundation
import FoundationModels

/// Structured extraction result for an RPG table's metadata.
/// Properties declared in generation order: title arrives first (~0.2s) for
/// progressive streaming UI before the full result is ready.
@Generable(description: "Extracted metadata from RPG table entries")
public struct TableSummaryAnalysis: Equatable, Sendable, Identifiable {

    public var id: String { title + description }

    @Guide(description: "A clear, concise title for the table")
    public var title: String

    @Guide(description: "A 1–2 sentence description of what the table contains or is used for")
    public var description: String

    @Guide(description: "Relevant RPG tags: genre, setting, mechanics, use case, etc.", .count(2...8))
    public var tags: [String]

    public init(title: String, description: String, tags: [String]) {
        self.title = title
        self.description = description
        self.tags = tags
    }
}
