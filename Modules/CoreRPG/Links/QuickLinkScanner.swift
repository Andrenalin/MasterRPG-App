// @copyright André Trettin

import Foundation

/// The quick linker: replaces the occurrences of a table's entry names in a text by links to
/// that table entry.
///
/// Matching is case-insensitive and whole-word. The longest name wins where two names overlap
/// (`Dire Wolf` before `Wolf`), and text that already sits inside a markdown link is left alone.
public enum QuickLinkScanner {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let count: Int
    }

    /// One link candidate per entry of `table`, skipping entries without a usable name and
    /// entries named like a dice roll range (`1`, `5-10`), so numbers never turn into links.
    @MainActor
    public static func candidates(for table: some ItemDataAccessible) -> [LinkEntryModel] {
        candidates(tableId: table.id, module: type(of: table).typeId, entries: table.entries.map { (id: $0.id, name: $0.name) })
    }

    public static func candidates(tableId: UUID, module: NetworkModules, entries: [(id: UUID, name: String)]) -> [LinkEntryModel] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            let name = entry.name.withoutLink().trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespacesAndNewlines))
            guard !name.isEmpty,
                  !name.contains(where: { $0 == "[" || $0 == "]" }),
                  TableRollRange.selectorRange(for: name) == nil,
                  seen.insert(name.lowercased()).inserted else { return nil }
            return LinkEntryModel(
                reference: name,
                markdownUrl: LinkBuilder.markdown(name: name, module: module, itemId: tableId, entryId: entry.id)
            )
        }
    }

    public static func apply(_ candidates: [LinkEntryModel], to text: String) -> Result {
        let protectedRanges = text.ranges(of: /\[[^\]]*\]\([^)]*\)/)
        var replacements: [(range: Range<String.Index>, markdownUrl: String)] = []

        for candidate in candidates.sorted(by: { $0.reference.count > $1.reference.count }) where !candidate.reference.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: candidate.reference, options: .caseInsensitive, range: searchRange) {
                searchRange = range.upperBound..<text.endIndex
                guard isWholeWord(range, of: candidate.reference, in: text),
                      !protectedRanges.contains(where: { $0.overlaps(range) }),
                      !replacements.contains(where: { $0.range.overlaps(range) }) else { continue }
                replacements.append((range: range, markdownUrl: candidate.markdownUrl))
            }
        }
        guard !replacements.isEmpty else { return Result(text: text, count: 0) }

        var result = ""
        var position = text.startIndex
        for replacement in replacements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            result += text[position..<replacement.range.lowerBound]
            result += replacement.markdownUrl
            position = replacement.range.upperBound
        }
        result += text[position...]
        return Result(text: result, count: replacements.count)
    }

    /// A match is a whole word when it isn't glued to a letter or digit on a side where the
    /// reference itself starts or ends with one.
    private static func isWholeWord(_ range: Range<String.Index>, of reference: String, in text: String) -> Bool {
        if let first = reference.first, first.isLetter || first.isNumber,
           range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            if previous.isLetter || previous.isNumber { return false }
        }
        if let last = reference.last, last.isLetter || last.isNumber,
           range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLetter || next.isNumber { return false }
        }
        return true
    }
}
