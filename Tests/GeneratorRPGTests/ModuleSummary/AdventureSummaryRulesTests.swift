// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation
import Testing

@testable import GeneratorRPG

/// The code side of the Adventure "Extract Information": the level band and the character count
/// read from the text, the type tag in every output language, the tag order and the title cleanup.
/// No Apple Intelligence needed.
@Suite("Adventure summary rules")
struct AdventureSummaryRulesTests {

    // MARK: - Level

    @Test("Named levels are found", arguments: [
        ("For 3-5 characters of levels 2 to 4.", 2...4),
        ("Level: 7", 7...7),
        ("An adventure for level 3 characters", 3...3),
        ("Written for 5th-level characters.", 5...5),
        ("A 1st-level adventure for a party of four.", 1...1),
        ("for 1st to 4th level heroes", 1...4),
        ("Für 3 bis 5 Helden der Stufen 5 bis 8.", 5...8),
        ("Für Helden der 9. Stufe.", 9...9),
        ("Charaktere der Stufe 3", 3...3),
        ("3.-5. Stufe", 3...5),
        ("Levels 4–6", 4...6),
        ("pour personnages de niveau 2 à 4", 2...4)
    ])
    func levels(text: String, levels: ClosedRange<Int>) {
        #expect(AdventurePartyFacts(text: text).levels == levels)
    }

    @Test("Floors, years and texts without a level have none", arguments: [
        "The party climbs to the 2nd level of the tower.",
        "Level 2 of the dungeon is flooded.",
        "Im Jahr 1923 in Berlin.",
        "The lighthouse has been dark for three nights.",
        "Level 45 of the arcology",
        ""
    ])
    func noLevels(text: String) {
        #expect(AdventurePartyFacts(text: text).levels == nil)
    }

    @Test("Bands hold the middle of the named levels", arguments: [
        (1...1, "1-4"), (3...5, "1-4"), (4...6, "5-8"), (2...4, "1-4"), (5...8, "5-8"),
        (9...9, "9-12"), (12...12, "9-12"), (13...13, "13-16"), (17...20, "17-20")
    ])
    func band(levels: ClosedRange<Int>, band: String) {
        #expect(AdventurePartyFacts(levels: levels).levelBand == band)
    }

    // MARK: - Characters

    @Test("Named character counts are found", arguments: [
        ("For 3-5 characters of levels 2 to 4.", 3...5),
        ("Written for four to six player characters.", 4...6),
        ("for 4 PCs", 4...4),
        ("A 1st-level adventure for a party of four.", 4...4),
        ("Für 3 bis 5 Helden der Stufen 5 bis 8.", 3...5),
        ("Für eine Gruppe von 4 Spielercharakteren.", 4...4),
        ("2 Spieler", 2...2),
        ("Für vier SC", 4...4),
        ("para 3 a 5 jugadores", 3...5)
    ])
    func characters(text: String, characters: ClosedRange<Int>) {
        #expect(AdventurePartyFacts(text: text).characters == characters)
    }

    @Test("Story numbers are no character count", arguments: [
        "Two heroes of old lie buried here.",
        "Sieben verschüttete Bergleute warten.",
        "Three stops: a ferry, a ruined waystation and a pass.",
        "One of the guards is a spy.",
        "Bunks for thirty soldiers",
        ""
    ])
    func noCharacters(text: String) {
        #expect(AdventurePartyFacts(text: text).characters == nil)
    }

    @Test("The count uses the output language's abbreviation", arguments: [
        ("English", 3...5, "3-5 PC"), ("German", 4...4, "4 SC"), ("French", 2...4, "2-4 PJ"),
        ("Italian", 4...6, "4-6 PG"), ("Polish", 3...3, "3 BG"), ("Klingon", 3...3, "3 PC")
    ])
    func characterTag(language: String, characters: ClosedRange<Int>, tag: String) {
        #expect(AdventurePartyFacts(characters: characters).characterTag(in: language) == tag)
    }

    // MARK: - Type

    @Test("Every type has a name in every output language and is explained to the model")
    func kindNamesComplete() {
        for kind in AdventurePlotKind.allCases {
            #expect(AdventurePlotKind.instructionList.contains("- \(kind.rawValue): "))
            for language in MapPlaceKind.languages {
                #expect(!kind.name(in: language).isEmpty, "\(kind) has no \(language) name")
            }
        }
        #expect(AdventurePlotKind.guarding.name(in: "German") == "Bewachung")
        #expect(AdventurePlotKind.travel.name(in: "English") == "Travel")
    }

    // MARK: - Tags

    @Test("Level band, count and type come first, then the content tags")
    func tagOrder() {
        let tags = AdventureSummaryGeneration.tags(
            facts: AdventurePartyFacts(levels: 2...4, characters: 3...5),
            kind: .investigation,
            contentTags: ["Lighthouse", "Cult", "Tide", "Saltmere"],
            title: "The Drowned Light",
            outputLanguage: "English"
        )
        #expect(tags == ["1-4", "3-5 PC", "Investigation", "Lighthouse", "Cult"])
    }

    @Test("Without a level or a count the content tags fill the slots")
    func tagsWithoutFacts() {
        let tags = AdventureSummaryGeneration.tags(
            facts: AdventurePartyFacts(),
            kind: .heist,
            contentTags: ["Casino", "Space Station", "Betrayal"],
            title: "Operation Glass Orchid",
            outputLanguage: "English"
        )
        #expect(tags == ["Heist", "Casino", "Space Station", "Betrayal"])
    }

    @Test("Model tags that repeat the type, a level, a count, the title or a form word are dropped")
    func droppedTags() {
        let tags = AdventureSummaryGeneration.tags(
            facts: AdventurePartyFacts(levels: 5...8),
            kind: .investigation,
            contentTags: ["Ermittlung", "Stufe 5-8", "3-5 SC", "Fluch von Rabenstein", "Abenteuer", "Fluch", "Geist"],
            title: "Fluch von Rabenstein",
            outputLanguage: "German"
        )
        #expect(tags == ["5-8", "Ermittlung", "Fluch", "Geist"])
    }

    // MARK: - Title

    @Test("Form words leave the title", arguments: [
        ("Adventure: The Drowned Light", "The Drowned Light"),
        ("Lighthouse Adventure", "Lighthouse"),
        ("Abenteuer: Fluch von Rabenstein", "Fluch von Rabenstein"),
        ("Operation Glass Orchid", "Operation Glass Orchid"),
        ("Adventure", "Rescue")
    ])
    func cleanedTitle(title: String, cleaned: String) {
        #expect(AdventureSummaryGeneration.cleanedTitle(title, kind: .rescue, outputLanguage: "English") == cleaned)
    }

    @Test("The adventure module uses its own analyzer")
    func analyzerChoice() {
        #expect(TextSummaryAnalyzers.analyzer(for: .adventure) is AdventureSummaryAnalyzer)
    }
}

#endif
