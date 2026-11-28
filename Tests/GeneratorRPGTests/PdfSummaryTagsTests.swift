// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The PDF tags are built in code from the generated kind, genre and free tags, so the kind tag
/// is there and valid even when the model copies a category value or answers with a genre.
@Suite("PDF summary tags")
struct PdfSummaryTagsTests {
    @Test("Kind and genre lead the free tags")
    func kindAndGenreLead() {
        let tags = PdfSummaryAnalysis.tags(
            category: .inn,
            documentKind: "Gasthaus",
            genre: "Fantasy",
            tags: ["Speisen", "Wyndland", "Drachen"],
            title: "Zum blauen Wunder",
            outputLanguage: "German"
        )

        #expect(tags == ["Gasthaus", "Fantasy", "Speisen", "Wyndland", "Drachen"])
    }

    @Test("The model's exact kind word is kept")
    func exactKindIsKept() {
        let kind = PdfSummaryAnalysis.kindTag(
            documentKind: "Stadtbeschreibung", category: .placeDescription, genre: "Fantasy",
            title: "Valen Coladris", outputLanguage: "German"
        )

        #expect(kind == "Stadtbeschreibung")
    }

    @Test("An unusable kind is replaced by the category's name", arguments: [
        ("characterSheet", PdfDocumentCategory.characterSheet, "Charakterbogen"),
        ("adventure", .adventure, "Abenteuer"),
        ("Rollenspiel", .rulebook, "Regelwerk"),
        ("Horror", .characterSheet, "Charakterbogen"),
        ("Wurzelnest", .adventure, "Abenteuer"),
        ("", .inn, "Gasthaus"),
        ("Typ: Abenteuer für vier Helden", .adventure, "Abenteuer")
    ])
    func unusableKindFallsBack(documentKind: String, category: PdfDocumentCategory, expected: String) {
        let kind = PdfSummaryAnalysis.kindTag(
            documentKind: documentKind, category: category, genre: "Horror",
            title: "Wurzelnest", outputLanguage: "German"
        )

        #expect(kind == expected)
    }

    @Test("English output keeps the English category word")
    func englishCategoryWord() {
        let kind = PdfSummaryAnalysis.kindTag(
            documentKind: "rulebook", category: .rulebook, genre: "Science fiction",
            title: "Starlane Protocol", outputLanguage: "English"
        )

        #expect(kind == "Rulebook")
    }

    @Test("While streaming an unusable kind is left out")
    func streamingDropsUnusableKind() {
        let tags = PdfSummaryAnalysis.tags(
            category: .characterSheet,
            documentKind: "characterSheet",
            genre: "Horror",
            tags: ["Berlin", "Kolonialzeit", "Okkultismus"],
            title: "Botho Phillip zu Eulenburg",
            outputLanguage: nil
        )

        #expect(tags == ["Horror", "Berlin", "Kolonialzeit", "Okkultismus"])
    }

    @Test("The title, generic tags and repeats go, five remain at most")
    func cleanedAndCapped() {
        let tags = PdfSummaryAnalysis.tags(
            category: .adventure,
            documentKind: "Abenteuer",
            genre: "Fantasy",
            tags: ["Wurzelnest", "Rollenspiel", "Kobolde", "Ratten", "Fantasy", "Kult"],
            title: "Wurzelnest",
            outputLanguage: "German"
        )

        #expect(tags == ["Abenteuer", "Fantasy", "Kobolde", "Ratten", "Kult"])
    }

    @Test("Every category has a name in every output language")
    func everyCategoryHasNames() {
        for category in PdfDocumentCategory.allCases {
            for language in MapPlaceKind.languages {
                #expect(category.name(in: language) != category.rawValue, "\(category) in \(language)")
            }
        }
        #expect(PdfDocumentCategory.inn.name(in: "Klingon") == "Inn")
    }

    @Test("Kind and genre take two slots, one spare free tag fills a dropped one")
    func freeTagCount() {
        #expect(PdfSummaryAnalysis.freeTagCountRange == 3...4)
    }
}

#endif
