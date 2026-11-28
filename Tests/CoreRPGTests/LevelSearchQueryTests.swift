// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// The global level search: reading "level 4 adventures" from a spoken or typed search, the
/// adventure level from tags and text, and a monster's level or challenge rating.
@Suite("Level search query")
struct LevelSearchQueryTests {

    // MARK: - Parsing

    @Test("Spoken requests become a level, a kind and no leftover text", arguments: [
        ("Give me level 4 adventures", 4, LevelSearchKind?.some(.adventure)),
        ("Any monster for level 9 characters", 9, .some(.monster)),
        ("level 4 adventures", 4, .some(.adventure)),
        ("4th level adventures", 4, .some(.adventure)),
        ("monsters lvl12", 12, .some(.monster)),
        ("CR 5", 5, .some(.monster)),
        ("challenge rating 3", 3, .some(.monster)),
        ("Level four", 4, nil),
        ("Abenteuer für Stufe 3", 3, .some(.adventure)),
        ("Gib mir Monster für Stufe 9 Helden", 9, .some(.monster)),
        ("Zeige Gegner mit HG 7", 7, .some(.monster)),
        ("level 5 adventures and monsters", 5, nil)
    ])
    func parsesSpokenRequests(text: String, level: Int, kind: LevelSearchKind?) throws {
        let query = try #require(LevelSearchQuery(parsing: text))
        #expect(query.filter.level == level)
        #expect(query.filter.kind == kind)
        #expect(query.text.isEmpty, "'\(query.text)' was left over")
    }

    @Test("Words that are no filler stay as the text")
    func keepsTheRemainingWords() throws {
        let query = try #require(LevelSearchQuery(parsing: "Red Dragon level 9"))
        #expect(query.filter == LevelSearchFilter(level: 9))
        #expect(query.text == "Red Dragon")
    }

    @Test("Text without a level is no level search", arguments: [
        "Goblin cave", "level", "level 0", "level 31", "the 2nd floor", "elf level", "Dragon 5"
    ])
    func rejectsTextWithoutALevel(text: String) {
        #expect(LevelSearchQuery(parsing: text) == nil)
    }

    // MARK: - Matching

    @Test("A monster matches within one level, closer is better")
    func monsterTolerance() {
        let filter = LevelSearchFilter(level: 9, kind: .monster)
        #expect(filter.monsterDistance(rating: 9) == 0)
        #expect(filter.monsterDistance(rating: 8) == 1)
        #expect(filter.monsterDistance(rating: 10) == 1)
        #expect(filter.monsterDistance(rating: 7) == nil)
        #expect(filter.monsterDistance(rating: 10.5) == nil)
    }

    @Test("An adventure matches when its levels hold the searched level")
    func adventureRange() {
        let filter = LevelSearchFilter(level: 4)
        #expect(filter.matchesAdventure(levels: 1...4))
        #expect(filter.matchesAdventure(levels: 4...4))
        #expect(!filter.matchesAdventure(levels: 5...8))
        #expect(filter.includes(.adventure) && filter.includes(.monster))
        #expect(!LevelSearchFilter(level: 4, kind: .monster).includes(.adventure))
    }

    // MARK: - Adventure levels

    @Test("Adventure levels come from the level tag first, then the text")
    func adventureLevels() {
        #expect(AdventurePartyFacts.adventureLevels(tags: ["Dungeon", "1-4", "4 PC"], name: "", description: "") == 1...4)
        #expect(AdventurePartyFacts.adventureLevels(tags: ["Level 6"], name: "", description: "") == 6...6)
        #expect(AdventurePartyFacts.adventureLevels(tags: ["Stufe 3-5"], name: "", description: "") == 3...5)
        #expect(AdventurePartyFacts.adventureLevels(tags: ["Ghosts"], name: "Crypt", description: "An adventure for level 3 characters.") == 3...3)
        #expect(AdventurePartyFacts.adventureLevels(tags: ["4 PC"], name: "Tower", description: "The 2nd level of the tower") == nil)
    }

    // MARK: - Monster ratings

    @Test("Rating values", arguments: [
        ("9", 9.0), ("1/4", 0.25), ("0.5", 0.5), ("2,5", 2.5), ("9 (5,000 XP)", 9.0), (" 12 ", 12.0)
    ])
    func ratingValues(value: String, rating: Double) {
        #expect(LevelSearchQuery.rating(from: value) == rating)
    }

    @Test("Values without a rating", arguments: ["", "high", "1/0", "45", "100"])
    func noRating(value: String) {
        #expect(LevelSearchQuery.rating(from: value) == nil)
    }

    @Test("Entry names that hold a rating")
    func ratingEntryNames() {
        for name in ["Level", "CR", "cr", "Challenge Rating", "Stufe", "HG", " level "] {
            #expect(LevelSearchQuery.isRatingEntryName(name), "\(name)")
        }
        for name in ["HP", "Initiative", "Level Up", "Armor Class"] {
            #expect(!LevelSearchQuery.isRatingEntryName(name), "\(name)")
        }
    }
}
