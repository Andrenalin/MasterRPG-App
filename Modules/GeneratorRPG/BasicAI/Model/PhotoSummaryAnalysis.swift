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
        description: GeneratedTagRules.guideDescription(
            contents: """
            One tag says what kind of image this is. One says what the main subject is. The \
            others name specific things you can see: creatures, places, objects, mood.
            """,
            extraGenericTags: PhotoSummaryAnalysis.genericTags
        ),
        .count(GeneratedTagRules.countRange)
    )
    public var tags: [String]

    /// Words that fit every image and so say nothing about this one.
    static let genericTags = ["Image", "Art", "Artwork", "Illustration"]

    public init(title: String, summary: String, tags: [String]) {
        self.title = title
        self.summary = summary
        self.tags = tags
    }
}
