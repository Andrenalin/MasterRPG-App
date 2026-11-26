// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation

/// Flattens a module title plus a sequence of name/content pairs into the
/// plain-text block `TextSummaryExtractionView`'s `entriesText` expects.
/// Every module previously hand-copied the same "- name: content" join
/// logic in its own `*ExtractionDestination.swift`. See CODE_AUDIT_Table §9.7.
public enum TextSummaryExtractionFormatter {
    public static func formatEntries(
        title: String,
        name: String,
        entries: [(name: String, content: String)]
    ) -> String {
        var lines: [String] = []
        if !name.isEmpty {
            lines.append("\(title): \(name)")
            lines.append("")
        }
        for entry in entries {
            lines.append(entry.content.isEmpty ? "- \(entry.name)" : "- \(entry.name): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }

    /// Longest portrait description passed along, so a long photo text does not push the
    /// character's own values out of the model's input.
    static let maximumPortraitDescriptionLength = 600

    /// A character sheet for `CharacterSummaryAnalyzer`: the values with their markdown links
    /// reduced to the labels (values are mostly formulas over other values, and the link URLs
    /// would only use up the model's input), then the portrait photo's description and tags.
    /// Used by the Character extraction screen and the batch, and by the evaluation.
    public static func formatCharacter(
        title: String,
        name: String,
        entries: [(name: String, content: String)],
        portraitDescription: String = "",
        portraitTags: [String] = []
    ) -> String {
        var text = formatEntries(
            title: title,
            name: name,
            entries: entries.map { ($0.name.withoutLink(), $0.content.withoutLink()) }
        )
        let description = String(portraitDescription.withoutLink()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumPortraitDescriptionLength))
        let tags = portraitTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !description.isEmpty || !tags.isEmpty else { return text }
        text += "\n"
        if !description.isEmpty {
            text += "\nPortrait: \(description)"
        }
        if !tags.isEmpty {
            text += "\nPortrait tags: \(tags.joined(separator: ", "))"
        }
        return text
    }
}

#endif
