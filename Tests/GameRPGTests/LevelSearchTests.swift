// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG
@testable import CharacterRPG
@testable import GameRPG

/// The level search of the global search: "Give me level 4 adventures" (Siri via
/// `GameRoot.showSearchResults`) and "Any monster for level 9 characters".
@MainActor
@Suite("Global level search")
struct LevelSearchTests {

    // MARK: - Model

    @Test("A level term from Siri becomes the token and its leftover words the text")
    func levelTermBecomesToken() {
        let model = GlobalSearchModel()
        model.show(term: "level 9 dragon monsters")

        #expect(model.levelTokens == [LevelSearchFilter(level: 9, kind: .monster)])
        #expect(model.searchText == "dragon")
        #expect(model.levelQuery == LevelSearchQuery(filter: LevelSearchFilter(level: 9, kind: .monster), text: "dragon"))
    }

    @Test("Any other term replaces the token with plain text")
    func plainTermClearsToken() {
        let model = GlobalSearchModel()
        model.levelTokens = [LevelSearchFilter(level: 4)]
        model.show(term: "Goblin cave")

        #expect(model.levelTokens.isEmpty)
        #expect(model.searchText == "Goblin cave")
        #expect(model.levelQuery == nil)
        #expect(model.hasSearch)
    }

    @Test("Typed level text is a level search without a token")
    func typedLevelText() {
        let model = GlobalSearchModel(searchText: "level 4 adventures")
        #expect(model.levelTokens.isEmpty)
        #expect(model.levelQuery?.filter == LevelSearchFilter(level: 4, kind: .adventure))
    }

    @Test("A token alone is a search")
    func tokenAloneIsASearch() {
        let model = GlobalSearchModel()
        #expect(!model.hasSearch)
        model.levelTokens = [LevelSearchFilter(level: 2)]
        #expect(model.hasSearch)
    }

    // MARK: - Search

    @Test("Level 4 adventures: the band tag and the text match, other levels do not")
    func findsAdventuresByLevel() async throws {
        let root = try await MockRoot.createGameRoot()
        await root.adventureRoot.itemController.resetData()
        let banded = await addAdventure(root, name: "Goblin Warrens", tags: ["Dungeon", "1-4"])
        let described = await addAdventure(root, name: "Haunted Mill", description: "An adventure for level 4 characters.")
        let tooHigh = await addAdventure(root, name: "Dragon Peak", tags: ["9-12"])
        let noLevel = await addAdventure(root, name: "Quiet Village")

        root.showSearchResults(for: "Give me level 4 adventures")
        await root.searchController.performSearch()

        let ids = Set(root.searchController.model.results[.adventure, default: []].map(\.itemId))
        #expect(ids.contains(banded))
        #expect(ids.contains(described))
        #expect(!ids.contains(tooHigh))
        #expect(!ids.contains(noLevel))
        #expect(root.searchController.model.results[.value, default: []].isEmpty, "an adventure search finds no monsters")
    }

    @Test("Monsters for level 9: level or CR within one, also in a Foundry details group")
    func findsMonstersByLevel() async throws {
        let root = try await MockRoot.createGameRoot()
        await root.characterRoot.itemController.resetData()

        let exact = addCharacter(root, name: "Troll", category: .monster, entries: [entry("CR", "9")])
        let near = addCharacter(root, name: "Hydra", category: .monster, entries: [entry("Level", "10")])
        let far = addCharacter(root, name: "Goblin", category: .monster, entries: [entry("CR", "1/4")])
        let hero = addCharacter(root, name: "Aria", category: .character, entries: [entry("Level", "9")])

        // Foundry: details → cr
        let foundry = UUID()
        let details = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: details, name: "details", entries: [entry("cr", "8")], groupId: foundry),
            isInsert: true
        )
        root.characterRoot.itemController.replace(
            model: ValueModel(id: foundry, name: "Young Dragon", category: .monster, entries: [
                ValueEntryModel(id: UUID(), name: "details", type: .text, value: "", valueId: details)
            ]),
            isInsert: true
        )

        root.showSearchResults(for: "Any monster for level 9 characters")
        await root.searchController.performSearch()

        let results = root.searchController.model.results[.value, default: []]
        let ids = results.map(\.itemId)
        #expect(Set(ids) == [exact, near, foundry])
        #expect(ids.first == exact, "the exact rating comes first")
        #expect(!ids.contains(far) && !ids.contains(hero))
        #expect(root.searchController.model.results[.adventure, default: []].isEmpty)
    }

    @Test("Player mode leaves adventures out of the level search")
    func playerModeHidesAdventures() async throws {
        let root = try await MockRoot.createGameRoot()
        await root.adventureRoot.itemController.resetData()
        _ = await addAdventure(root, name: "Goblin Warrens", tags: ["1-4"])

        root.searchController.model.playerMode = true
        root.showSearchResults(for: "level 4 adventures")
        await root.searchController.performSearch()

        #expect(root.searchController.model.results[.adventure] == nil)
    }

    // MARK: - Helpers

    private func addAdventure(_ root: GameRoot, name: String, description: String = "", tags: [String] = []) async -> UUID {
        let adventureRoot = root.adventureRoot
        let itemId = await adventureRoot.itemController.addNew(type: .item)
        adventureRoot.editController.reset(name: name, itemId: itemId, forceSave: false)
        if !description.isEmpty {
            adventureRoot.editController.reset(description: description, itemId: itemId, forceSave: false)
        }
        if !tags.isEmpty {
            adventureRoot.editController.reset(tags: tags, itemId: itemId, forceSave: false)
        }
        return itemId
    }

    private func addCharacter(_ root: GameRoot, name: String, category: ItemListCategory, entries: [ValueEntryModel]) -> UUID {
        let id = UUID()
        root.characterRoot.itemController.replace(
            model: ValueModel(id: id, name: name, category: category, entries: entries),
            isInsert: true
        )
        return id
    }

    private func entry(_ name: String, _ value: String) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: .text, value: value)
    }
}
