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
        let title = legacyCategory.title
        // Not added twice when the item already carries the title. See CODE_AUDIT_26 §5.54.
        let all = tags.contains(title) ? tags : [title] + tags
        return all.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}
