// @copyright André Trettin

import Foundation
import FoundationModels

/// Title, description and tags the model reads from one photo.
///
/// Properties are generated in declaration order, so the title comes first like in
/// `PdfSummaryAnalysis`.
@Generable(description: "Title, short description and tags of an image from a role-playing game: art, portrait, map, handout or scene")
public struct PhotoSummaryAnalysis: Equatable, Sendable, Codable {

    @Guide(description: "A short title that names the main subject of the image")
    public var title: String

    @Guide(description: "A concise description of what is visible in the image (2-3 sentences)")
    public var summary: String

    @Guide(
        description: """
        3 to 5 short tags of 1 to 3 words, written in the output language. One tag says what kind \\
        of image this is. One says what the main subject is. The others name specific things you \\
        can see: creatures, places, objects, mood. No generic tags such as RPG, Setting, System, \\
        Genre, Image or Illustration, and no labels or colons.
        """,
        .count(3...5)
    )
    public var tags: [String]

    public init(title: String, summary: String, tags: [String]) {
        self.title = title
        self.summary = summary
        self.tags = tags
    }
}
