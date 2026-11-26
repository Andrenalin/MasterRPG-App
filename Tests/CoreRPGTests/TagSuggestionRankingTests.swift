// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@MainActor
@Suite("Tag suggestions for the add-tag field")
struct TagSuggestionRankingTests {
    private let module = NetworkModules.photo

    private func tag(_ title: String, _ count: Int) -> TagModel {
        TagModel(module: module, title: title, count: count)
    }

    private var library: [TagModel] {
        [
            tag("DRAGON", 12),
            tag("CAVE", 7),
            tag("BOSS", 3),
            tag("DUNGEON", 9),
            tag("RED DRAGON", 20),
            tag("UNUSED", 0),
        ]
    }

    @Test("Without text, the three most used tags")
    func emptySearchShowsTopThree() {
        let titles = TagSuggestionRanking.suggestions(from: library, search: "", excluding: []).map(\.title)
        #expect(titles == ["RED DRAGON", "DRAGON", "DUNGEON"])
    }

    @Test("Blank text counts as no text")
    func blankSearchShowsTopThree() {
        let titles = TagSuggestionRanking.suggestions(from: library, search: "  ", excluding: []).map(\.title)
        #expect(titles == ["RED DRAGON", "DRAGON", "DUNGEON"])
    }

    @Test("Typed text matches case-insensitively, tags starting with it before more used ones containing it")
    func searchRanksPrefixFirst() {
        let suggestions = TagSuggestionRanking.suggestions(from: library, search: "drag", excluding: [])
        #expect(suggestions.map(\.title) == ["DRAGON", "RED DRAGON"])
        #expect(suggestions.map(\.count) == [12, 20])
    }

    @Test("Tags the item already has are not suggested, in any case")
    func excludesExistingTags() {
        let titles = TagSuggestionRanking.suggestions(from: library, search: "", excluding: ["red dragon", "DRAGON"]).map(\.title)
        #expect(titles == ["DUNGEON", "CAVE", "BOSS"])
    }

    @Test("Unused and untitled tags are not suggested, case duplicates show once")
    func skipsUnusedAndDuplicates() {
        let tags = [tag("UNUSED", 0), tag("", 4), tag("Forest", 2), tag("FOREST", 5)]
        let titles = TagSuggestionRanking.suggestions(from: tags, search: "", excluding: []).map(\.title)
        #expect(titles.count == 1)
        #expect(titles.first?.localizedUppercase == "FOREST")
    }

    @Test("Equal counts are sorted by title, typed results are capped")
    func tiesAndLimit() {
        let tags = (1...8).map { tag("TAG \($0)", 1) }
        let titles = TagSuggestionRanking.suggestions(from: tags, search: "tag", excluding: []).map(\.title)
        #expect(titles == ["TAG 1", "TAG 2", "TAG 3", "TAG 4", "TAG 5"])
    }

    @Test("Text matching nothing gives no suggestions")
    func noMatch() {
        #expect(TagSuggestionRanking.suggestions(from: library, search: "zzz", excluding: []).isEmpty)
    }

    @Test("The controller suggests only the requested module's tags and follows its counts")
    func controllerUsesModuleTags() {
        let controller = TagController()
        controller.add(tags: ["CAVE", "CAVE", "BOSS"], module: module)
        controller.add(tags: ["SPELL"], module: .table)

        #expect(controller.suggestions(module: module, search: "", excluding: []).map(\.title) == ["CAVE", "BOSS"])

        controller.add(tags: ["BOSS", "BOSS"], module: module)
        #expect(controller.suggestions(module: module, search: "", excluding: []).map(\.title) == ["BOSS", "CAVE"])
        #expect(controller.suggestions(module: module, search: "spe", excluding: []).isEmpty)
    }
}
