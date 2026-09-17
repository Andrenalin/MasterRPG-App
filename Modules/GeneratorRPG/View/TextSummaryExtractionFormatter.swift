// @copyright André Trettin

#if !os(tvOS)

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
}

#endif
