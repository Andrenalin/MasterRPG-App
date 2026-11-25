// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
struct ImportItemRepairTests {
    @Test func legacyCategoryIsConvertedToEntryAndCategoryTag() {
        var item = FakeItemModel(name: "Legacy Adventure", category: .adventure, tags: ["Campaign"])

        ImportItemRepair.normalizeLegacyCategory(in: &item)

        #expect(item.category == .entry)
        #expect(item.tags == ["Adventure", "Campaign"])
    }

    @Test func newDataModelCategoriesAreLeftUnchanged() {
        var entry = FakeItemModel(name: "Entry", category: .entry, tags: ["A"])
        var folder = FakeItemModel(name: "Folder", category: .folder, tags: ["B"])
        var collection = FakeItemModel(name: "Collection", category: .collection, tags: ["C"])

        ImportItemRepair.normalizeLegacyCategory(in: &entry)
        ImportItemRepair.normalizeLegacyCategory(in: &folder)
        ImportItemRepair.normalizeLegacyCategory(in: &collection)

        #expect(entry.category == .entry)
        #expect(entry.tags == ["A"])
        #expect(folder.category == .folder)
        #expect(folder.tags == ["B"])
        #expect(collection.category == .collection)
        #expect(collection.tags == ["C"])
    }

    @Test func legacyItemCategoryBecomesEntryWithoutItemTag() {
        var item = FakeItemModel(name: "Legacy Item", category: .item, tags: ["Equipment"])

        ImportItemRepair.normalizeLegacyCategory(in: &item)

        #expect(item.category == .entry)
        #expect(item.tags == ["Equipment"])
    }

    @Test func itemCategoryTagIsRemovedInEveryLanguage() {
        let tags = ["Item", "Gegenstand", "item", "Ambient", ItemListCategory.item.title]

        #expect(ImportItemRepair.removingItemCategoryTags(from: tags) == ["Ambient"])
    }
}
