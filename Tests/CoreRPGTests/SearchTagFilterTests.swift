// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.14: selected tag tokens narrow the search results.
@MainActor
@Suite("Search tag tokens")
struct SearchTagFilterTests {
    private func result(_ id: UUID, children: [SearchResult] = []) -> SearchResult {
        var result = SearchResult(itemId: id, itemName: "Item", module: .adventure, category: .scenario, relevanceScore: 0)
        result.children = children
        return result
    }

    @Test("An item needs every selected tag, compared case-insensitively as a whole tag")
    func matchesNeedsAllTokens() {
        #expect(SearchTagFilter.matches(itemTags: ["Dragon", "Cave"], tokens: ["dragon"]))
        #expect(SearchTagFilter.matches(itemTags: ["Dragon", "Cave"], tokens: ["Dragon", "cave"]))
        #expect(!SearchTagFilter.matches(itemTags: ["Dragon"], tokens: ["Dragon", "Cave"]))
        #expect(!SearchTagFilter.matches(itemTags: ["Dragons"], tokens: ["Dragon"]), "a part of a tag is not the tag")
        #expect(SearchTagFilter.matches(itemTags: [], tokens: []))
    }

    @Test("Results without tokens are returned unchanged")
    func noTokensKeepsEverything() {
        let results = [result(UUID()), result(UUID())]
        #expect(SearchTagFilter.filter(results, tokens: [], tags: { _ in [] }) == results)
    }

    @Test("Only tagged items remain, unknown items are dropped")
    func filtersFlatResults() {
        let tagged = UUID()
        let other = UUID()
        let unknown = UUID()
        let tags: [UUID: [String]] = [tagged: ["Dragon"], other: ["Elf"]]

        let filtered = SearchTagFilter.filter([result(tagged), result(other), result(unknown)], tokens: ["Dragon"]) { tags[$0] }

        #expect(filtered.map(\.itemId) == [tagged])
    }

    @Test("A folder is kept for the tagged items inside it and shows only those")
    func keepsContainersOfMatches() {
        let folder = UUID()
        let match = UUID()
        let miss = UUID()
        let emptyFolder = UUID()
        let nested = UUID()
        let tags: [UUID: [String]] = [match: ["Dragon"], miss: ["Elf"], folder: [], emptyFolder: [], nested: ["Elf"]]
        let tree = [
            result(folder, children: [result(match), result(miss)]),
            result(emptyFolder, children: [result(nested)]),
        ]

        let filtered = SearchTagFilter.filter(tree, tokens: ["Dragon"]) { tags[$0] }

        #expect(filtered.map(\.itemId) == [folder])
        #expect(filtered.first?.children.map(\.itemId) == [match])
    }

    @Test("A typed @ entry is a tag lookup and does not search text")
    func atEntriesAreNotTextSearches() {
        #expect(SearchModel.searchText(forField: "@dra") == "")
        #expect(SearchModel.searchText(forField: "@") == "")
        #expect(SearchModel.searchText(forField: "dra") == "dra")
        #expect(SearchModel.searchText(forField: "mail@home") == "mail@home")
    }

    @Test("Picking a suggestion adds the token once and clears the field")
    func selectingATokenClearsTheField() {
        let model = SearchModel.preview()
        model.searchFieldText = "@dra"
        model.searchTags = [SearchTags(tag: "Dragon")]

        model.select(token: SearchTags(tag: "Dragon"))
        model.select(token: SearchTags(tag: "Dragon"))

        #expect(model.selectedTokens == [SearchTags(tag: "Dragon")])
        #expect(model.searchFieldText.isEmpty)
        #expect(model.searchTags.isEmpty)
    }
}
