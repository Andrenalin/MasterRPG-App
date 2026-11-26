// @copyright André Trettin

import Foundation

/// A tag the editor offers while someone types a new tag: an existing tag of the module and how
/// many items and entries use it.
public struct TagSuggestion: Hashable, Sendable, Identifiable {
    public let title: String
    public let count: Int

    public var id: String { title }
}

/// Picks the tag suggestions for the add-tag field. Pure, so the ranking can be tested without a store.
enum TagSuggestionRanking {
    /// Suggestions shown before anything is typed: the most used tags.
    static let emptySearchLimit = 3
    /// Suggestions shown while typing.
    static let searchLimit = 5

    /// With an empty (or blank) search, the most used tags. Otherwise the tags containing the search,
    /// tags starting with it first, each group most used first. Tags the item already has are left
    /// out (case-insensitively, the editor stores tags uppercased), ties are sorted by title.
    static func suggestions(
        from tags: some Sequence<TagModel>,
        search: String,
        excluding existing: [String],
        emptySearchLimit: Int = emptySearchLimit,
        searchLimit: Int = searchLimit
    ) -> [TagSuggestion] {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingKeys = Set(existing.map(key))
        var seenKeys: Set<String> = []
        let candidates = tags.filter { tag in
            guard tag.count > 0, !tag.title.isEmpty else { return false }
            // Titles that differ only in case would show as the same chip; keep one.
            let tagKey = key(tag.title)
            guard !existingKeys.contains(tagKey), seenKeys.insert(tagKey).inserted else { return false }
            return search.isEmpty || tag.title.localizedStandardContains(search)
        }

        let ranked = candidates.sorted { lhs, rhs in
            if !search.isEmpty {
                let lhsPrefix = startsWith(lhs.title, search)
                let rhsPrefix = startsWith(rhs.title, search)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
            }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return ranked
            .prefix(search.isEmpty ? emptySearchLimit : searchLimit)
            .map { TagSuggestion(title: $0.title, count: $0.count) }
    }

    private static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).localizedUppercase
    }

    private static func startsWith(_ title: String, _ search: String) -> Bool {
        title.range(of: search, options: [.anchored, .caseInsensitive, .diacriticInsensitive], locale: .current) != nil
    }
}

public extension TagController {
    /// The suggestions for the add-tag field of an item of `module`. Reads the observable tag table,
    /// so a view calling it from `body` updates when the tags change.
    @MainActor func suggestions(module: NetworkModules, search: String, excluding existing: [String]) -> [TagSuggestion] {
        TagSuggestionRanking.suggestions(
            from: model.tags[module, default: [:]].values,
            search: search,
            excluding: existing
        )
    }
}
