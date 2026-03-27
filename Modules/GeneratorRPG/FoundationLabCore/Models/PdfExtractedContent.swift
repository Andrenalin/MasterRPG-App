// @copyright André Trettin

#if !os(tvOS)

import Foundation
import FoundationModels

/// Structured content extracted from PDF documents
///
/// **Property Order Optimized for Streaming UX:**
/// Properties are generated in declaration order. Most important properties come first
/// so users see title in ~0.2s instead of waiting for full generation (~2-3s).
/// This follows Foundation Models best practice for progressive UI updates.
@Generable(description: "Structured metadata and content extracted from RPG rulebooks or adventure PDFs")
public struct PdfExtractedContent: Equatable, Sendable, Identifiable {

    public var id: String { title + summary }

    @Guide(description: "The main title or name of the document")
    public var title: String

    @Guide(description: "A concise summary of the PDF content (2-3 sentences)")
    public var summary: String

    @Guide(description: "Key topics, themes, or categories covered in the document", .count(3...8))
    public var tags: [String]

    @Guide(description: "Important sections, chapters, or major divisions found in the document")
    public var sections: [PdfSection]

    public init(title: String, summary: String, tags: [String], sections: [PdfSection]) {
        self.title = title
        self.summary = summary
        self.tags = tags
        self.sections = sections
    }
}

/// A section or chapter within the PDF
@Generable(description: "A major section or chapter in the PDF document")
public struct PdfSection: Equatable, Sendable {

    @Guide(description: "The section heading or chapter title")
    public var heading: String

    @Guide(description: "A brief summary of what this section covers")
    public var summary: String

    @Guide(description: "The approximate page number where this section starts, if identifiable")
    public var pageNumber: Int?

    public init(heading: String, summary: String, pageNumber: Int? = nil) {
        self.heading = heading
        self.summary = summary
        self.pageNumber = pageNumber
    }
}

#endif
