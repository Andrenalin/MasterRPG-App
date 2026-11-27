// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The code side of the Map "Extract Information": the kind tag in every output language, and the
/// cleanup that keeps "Map" out of the title and the tags. No Apple Intelligence needed.
@Suite("Map summary rules")
struct MapSummaryRulesTests {

    // MARK: - Kind names

    @Test("Every kind has a name in every output language")
    func kindNamesComplete() {
        #expect(MapPlaceKind.languages == OutputLanguage.supported.map(\.englishName))
        for kind in MapPlaceKind.allCases {
            for language in MapPlaceKind.languages {
                let name = kind.name(in: language)
                #expect(!name.isEmpty, "\(kind) has no \(language) name")
                #expect(MapSummaryGeneration.withoutFormWords(name, keepInnerFormWords: false) == name, "\(kind) in \(language) is a form word")
            }
        }
    }

    @Test("Kind names follow the output language, unknown languages get English", arguments: [
        (MapPlaceKind.cave, "English", "Cave"), (.cave, "German", "Höhle"), (.country, "German", "Land"),
        (.fortress, "French", "Forteresse"), (.spaceStation, "English", "Space Station"), (.swamp, "Klingon", "Swamp")
    ])
    func kindName(kind: MapPlaceKind, language: String, name: String) {
        #expect(kind.name(in: language) == name)
    }

    @Test("Every kind is explained to the model")
    func instructionListNamesEveryKind() {
        for kind in MapPlaceKind.allCases {
            #expect(MapPlaceKind.instructionList.contains("- \(kind.rawValue): "))
        }
    }

    // MARK: - Form words

    @Test("Form words at the start or end are removed", arguments: [
        ("Dungeon Map", "Dungeon"),
        ("Cave map", "Cave"),
        ("Blackwater Keep Map", "Blackwater Keep"),
        ("Map of Blackwater Keep", "Blackwater Keep"),
        ("Map: Sunken Crypt", "Sunken Crypt"),
        ("Karte der Gruft", "Gruft"),
        ("Carte du donjon", "donjon"),
        ("Mapa de la cueva", "cueva"),
        ("Floor Plan", ""),
        ("Deck Plan", ""),
        ("ダンジョンマップ", "ダンジョン"),
        ("Map", ""),
        ("Schatzkarte", "Schatzkarte"),
        ("Maple Grove", "Maple Grove")
    ])
    func formWordsRemoved(text: String, expected: String) {
        #expect(MapSummaryGeneration.withoutFormWords(text, keepInnerFormWords: true) == expected)
    }

    @Test("A tag with a form word inside is dropped, a title loses the word")
    func innerFormWord() {
        #expect(MapSummaryGeneration.withoutFormWords("Crypt Map Room", keepInnerFormWords: false) == "")
        #expect(MapSummaryGeneration.withoutFormWords("Crypt Map Room", keepInnerFormWords: true) == "Crypt Room")
    }

    // MARK: - Title and tags

    @Test("The title loses form words and falls back to the kind")
    func cleanedTitle() {
        #expect(MapSummaryGeneration.cleanedTitle("Sewer Map", kind: .sewer, outputLanguage: "English") == "Sewer")
        #expect(MapSummaryGeneration.cleanedTitle("Karte", kind: .cave, outputLanguage: "German") == "Höhle")
        #expect(MapSummaryGeneration.cleanedTitle("Map", kind: nil, outputLanguage: "English") == "")
    }

    @Test("The kind is the first tag; form words, duplicates of the kind and the title go")
    func tags() {
        let tags = MapSummaryGeneration.tags(
            kind: .cave,
            contentTags: ["Cave Map", "Goblins", "Floor Plan", "Underdark Map Pack", "Goblin Caves", "Glowing Fungi"],
            title: "Goblin Caves",
            outputLanguage: "English"
        )

        #expect(tags == ["Cave", "Goblins", "Glowing Fungi"])
    }

    @Test("The kind tag is written in the output language and a label is cut off")
    func germanTags() {
        let tags = MapSummaryGeneration.tags(
            kind: .country,
            contentTags: ["Landkarte", "Thema: Zwerge", "Orks", "Grenzfeste"],
            title: "Königreich Varn",
            outputLanguage: "German"
        )

        #expect(tags == ["Land", "Zwerge", "Orks", "Grenzfeste"])
    }

    @Test("A tag that names the kind in another language goes")
    func kindInOtherLanguage() {
        let tags = MapSummaryGeneration.tags(kind: .forest, contentTags: ["Wald", "Elves", "Forêt", "Grove"], title: "Elven Grove", outputLanguage: "English")

        #expect(tags == ["Forest", "Elves", "Grove"])
    }

    @Test("At most five tags, and none before the kind is known")
    func tagLimits() {
        let many = MapSummaryGeneration.tags(kind: .forest, contentTags: ["A", "B", "C", "D", "E"], title: "", outputLanguage: "English")
        #expect(many == ["Forest", "A", "B", "C", "D"])
        #expect(MapSummaryGeneration.tags(kind: nil, contentTags: ["Elves"], title: "", outputLanguage: "English") == ["Elves"])
        #expect(MapSummaryGeneration.contentTagRange == 2...4)
    }

    // MARK: - Evaluation rules

    @Test("The evaluation wants the kind as the first tag in the output language")
    func evaluationKindTag() {
        let english = TableSummaryEvaluator.mapViolations(title: "Fenmoor", tags: ["Swamp", "Lizardfolk", "Witch"], acceptedKinds: [.swamp], outputLanguage: "English")
        let missing = TableSummaryEvaluator.mapViolations(title: "Fenmoor", tags: ["Lizardfolk", "Swamp", "Witch"], acceptedKinds: [.swamp], outputLanguage: "English")
        let untranslated = TableSummaryEvaluator.mapViolations(title: "Varn", tags: ["Country", "Zwerge", "Orks"], acceptedKinds: [.country], outputLanguage: "German")

        #expect(english.tags.isEmpty)
        #expect(missing.tags.count == 1)
        #expect(untranslated.tags.count == 1)
    }

    @Test("The evaluation flags 'map' in the title and the tags", arguments: ["Dungeon Map", "Karte der Gruft", "Cave Layout"])
    func evaluationFormWords(text: String) {
        let result = TableSummaryEvaluator.mapViolations(title: text, tags: ["Crypt", text], acceptedKinds: [], outputLanguage: "English")

        #expect(result.title.count == 1)
        #expect(result.tags.count == 1)
    }

    @Test("A map fixture names its accepted kinds, an adventure none")
    func fixtureKinds() {
        #expect(ModuleSummaryFixture.maps.allSatisfy { !$0.mapKinds.isEmpty })
        #expect(ModuleSummaryFixture.adventures.allSatisfy { $0.mapKinds.isEmpty })
    }
}

#endif
