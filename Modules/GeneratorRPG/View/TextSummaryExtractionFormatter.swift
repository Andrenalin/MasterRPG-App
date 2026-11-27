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

    /// Longest photo description passed along, so a long photo text does not push the item's own
    /// entries out of the model's input.
    static let maximumPhotoDescriptionLength = 600

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
        formatWithPhoto(
            title: title,
            name: name,
            entries: entries,
            photoLabel: "Portrait",
            photoDescription: portraitDescription,
            photoTags: portraitTags
        )
    }

    /// A map for the Map "Extract Information": the rooms with their markdown links reduced to the
    /// labels, then the map photo's description and tags, which often say more about the place
    /// than the room names. Used by the Map extraction screen and the batch, and by the evaluation.
    public static func formatMap(
        title: String,
        name: String,
        entries: [(name: String, content: String)],
        photoDescription: String = "",
        photoTags: [String] = []
    ) -> String {
        formatWithPhoto(
            title: title,
            name: name,
            entries: entries,
            photoLabel: "Map photo",
            photoDescription: photoDescription,
            photoTags: photoTags
        )
    }

    /// The entries with links reduced to their labels, then "<label>: <description>" (cut at
    /// `maximumPhotoDescriptionLength`) and "<label> tags: <tags>", each left out when empty.
    /// The labels stay English: they are part of the prompt, not of the output.
    private static func formatWithPhoto(
        title: String,
        name: String,
        entries: [(name: String, content: String)],
        photoLabel: String,
        photoDescription: String,
        photoTags: [String]
    ) -> String {
        var text = formatEntries(
            title: title,
            name: name,
            entries: entries.map { ($0.name.withoutLink(), $0.content.withoutLink()) }
        )
        let description = String(photoDescription.withoutLink()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumPhotoDescriptionLength))
        let tags = photoTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !description.isEmpty || !tags.isEmpty else { return text }
        text += "\n"
        if !description.isEmpty {
            text += "\n\(photoLabel): \(description)"
        }
        if !tags.isEmpty {
            text += "\n\(photoLabel) tags: \(tags.joined(separator: ", "))"
        }
        return text
    }
}

#endif
