// @copyright André Trettin

import Foundation

public enum ImportItemRepair {
    public static func isNewDataModelCategory(_ category: ItemListCategory) -> Bool {
        category == .entry || category == .folder || category.isCollection
    }

    public static func shouldNormalizeLegacyCategory(_ category: ItemListCategory) -> Bool {
        !isNewDataModelCategory(category)
    }

    @MainActor
    public static func normalizeLegacyCategory<Model: ItemDataAccessible>(in item: inout Model) {
        guard shouldNormalizeLegacyCategory(item.category) else { return }
        let legacyCategory = item.category
        item.category = .entry
        item.tags = normalizedTags(legacyCategory: legacyCategory, tags: item.tags)
    }

    public static func normalizedTags(legacyCategory: ItemListCategory, tags: [String]) -> [String] {
        // `.item` was the plain item category, not a topic: it never becomes a tag.
        guard legacyCategory != .item else { return removingItemCategoryTags(from: tags) }
        let title = legacyCategory.title
        // Not added twice when the item already carries the title. See CODE_AUDIT_26 §5.54.
        let all = tags.contains(title) ? tags : [title] + tags
        return all.sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    /// The titles of `ItemListCategory.item` ("Item", "Gegenstand") that earlier Validate runs
    /// added as a tag. Current language plus English and German, since the tag keeps the
    /// language of the device that added it.
    static var itemCategoryTagTitles: [String] {
        var titles = [ItemListCategory.item.title]
        for identifier in ["en", "de"] {
            var resource = ItemListCategory.item.localizedTitle
            resource.locale = Locale(identifier: identifier)
            titles.append(String(localized: resource))
        }
        return titles
    }

    /// `tags` without the "Item" category tag, in their original order.
    public static func removingItemCategoryTags(from tags: [String]) -> [String] {
        let titles = itemCategoryTagTitles
        return tags.filter { tag in
            !titles.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }
}
