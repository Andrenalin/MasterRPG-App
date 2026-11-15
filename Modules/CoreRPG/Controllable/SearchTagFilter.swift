// @copyright André Trettin

import Foundation

/// Narrows search results to the items that carry every selected tag token (the `@` suggestions
/// of the search field). The tokens used to be shown as chips only; nothing read them.
/// See CODE_AUDIT_26 §5.14.
public enum SearchTagFilter {
    /// Whether `itemTags` hold every one of `tokens` (case-insensitive, whole tag).
    public static func matches(itemTags: [String], tokens: [String]) -> Bool {
        tokens.allSatisfy { token in
            itemTags.contains { $0.localizedCaseInsensitiveCompare(token) == .orderedSame }
        }
    }

    /// `results` without the nodes that neither carry every token themselves nor contain a node
    /// that does. A container that is kept only for its descendants shows just those. With no
    /// tokens the results are returned unchanged.
    /// - Parameter tags: the tags of an item, `nil` when the item is not known.
    @MainActor
    public static func filter(_ results: [SearchResult], tokens: [String], tags: (UUID) -> [String]?) -> [SearchResult] {
        guard !tokens.isEmpty else { return results }
        return results.compactMap { result in
            var result = result
            result.children = filter(result.children, tokens: tokens, tags: tags)
            let matchesItself = tags(result.itemId).map { matches(itemTags: $0, tokens: tokens) } ?? false
            return matchesItself || !result.children.isEmpty ? result : nil
        }
    }
}

extension SearchRootControllable {
    /// `results` narrowed by the tag tokens selected in `searchModel`.
    @MainActor func applyingSelectedTags(to results: [SearchResult], itemControllable: any ItemControllable) -> [SearchResult] {
        SearchTagFilter.filter(results, tokens: searchModel.selectedTokens.map(\.tag)) {
            itemControllable.itemSync(for: $0)?.tags
        }
    }
}
