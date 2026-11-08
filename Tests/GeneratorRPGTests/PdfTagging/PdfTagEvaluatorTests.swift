// @copyright André Trettin

#if !os(tvOS)

import Foundation
import PDFKit
import Testing

@testable import GeneratorRPG

/// The scoring rules and the fixtures themselves. These need no Apple Intelligence and run in
/// every test run, so a broken evaluation is found before it judges the model.
@Suite("PDF tag evaluator")
struct PdfTagEvaluatorTests {
    private let evaluator = PdfTagEvaluator()
    private let expectation = PdfTagExpectation(
        conceptGroups: [["dungeon", "crypt"], ["fantasy"], ["undead", "skeleton"]],
        minimumMatchedGroups: 2,
        forbiddenTerms: ["castle"]
    )

    @Test("Good tags pass")
    func goodTags() {
        let result = evaluator.evaluate(
            tags: ["Fantasy", "Dungeon crawl", "Undead", "Treasure"],
            title: "The Crypt of the Ash King",
            expectation: expectation
        )

        #expect(result.passed)
        #expect(result.matchedGroups == [0, 1, 2])
    }

    @Test("Count outside 3 to 5 fails", arguments: [
        ["Fantasy", "Dungeon"],
        ["Fantasy", "Dungeon", "Undead", "Loot", "Traps", "Gold"]
    ])
    func countRange(tags: [String]) {
        let result = evaluator.evaluate(tags: tags, title: "T", expectation: expectation)

        #expect(result.violations.contains { $0.contains("tag count") })
    }

    @Test("Empty and duplicate tags fail, ignoring case and diacritics")
    func emptyAndDuplicates() {
        let result = evaluator.evaluate(
            tags: ["Fantasy", "fantasy ", " ", "Dungeon"],
            title: "T",
            expectation: expectation
        )

        #expect(result.violations.contains("empty tag"))
        #expect(result.violations.contains { $0.contains("duplicate tag") })
        #expect(PdfTagEvaluator.normalized("Café") == PdfTagEvaluator.normalized("cafe"))
    }

    @Test("Sentences, long tags, file words and the title fail")
    func badShapes() {
        let result = evaluator.evaluate(
            tags: [
                "A dungeon adventure for brave heroes.",
                "This tag is much too long to be a tag at all really",
                "PDF",
                "Ash King"
            ],
            title: "Ash King",
            expectation: expectation
        )

        #expect(result.violations.contains { $0.contains("reads like a sentence") })
        #expect(result.violations.contains { $0.contains("more than 4 words") })
        #expect(result.violations.contains { $0.contains("longer than 40 characters") })
        #expect(result.violations.contains { $0.contains("describes the file") })
        #expect(result.violations.contains { $0.contains("repeats the title") })
    }

    @Test("Forbidden terms fail")
    func forbiddenTerm() {
        let result = evaluator.evaluate(
            tags: ["Fantasy", "Dungeon", "Haunted Castle"],
            title: "T",
            expectation: expectation
        )

        #expect(result.violations.contains { $0.contains("forbidden term 'castle'") })
    }

    @Test("Generic and prompt-label tags fail", arguments: [
        "RPG", "Setting", "System", "genre", "Role-Playing", "Rollenspiel",
        "Genre: Horror", "Setting (1893, village)"
    ])
    func genericTagsFail(tag: String) {
        let result = evaluator.evaluate(
            tags: ["Fantasy", "Dungeon", tag],
            title: "T",
            expectation: expectation
        )

        #expect(!result.passed)
        #expect(result.violations.contains { $0.contains("'\(tag)'") })
    }

    @Test("Specific tags that merely contain a generic word pass")
    func specificTagsPass() {
        let result = evaluator.evaluate(
            tags: ["Percentile system", "Fantasy setting", "Dungeon"],
            title: "T",
            expectation: expectation
        )

        #expect(result.passed)
    }

    @Test("Too few matched concepts fail and name the missing ones")
    func missingConcepts() {
        let result = evaluator.evaluate(
            tags: ["Cooking", "Travel", "Gardening"],
            title: "T",
            expectation: expectation
        )

        #expect(result.matchedGroups.isEmpty)
        #expect(result.violations.contains { $0.contains("matched 0 of 2 required concepts") })
        #expect(result.recall == 0)
    }

    @Test("Without a minimum all concept groups are required")
    func allGroupsRequired() {
        let strict = PdfTagExpectation(conceptGroups: [["a"], ["b"]])

        #expect(strict.requiredGroupCount == 2)
        #expect(evaluator.evaluate(tags: ["a1", "b1", "c1"], title: "T", expectation: strict).passed)
        #expect(!evaluator.evaluate(tags: ["a1", "c1", "d1"], title: "T", expectation: strict).passed)
    }

    @Test("Every expected bundled PDF is in the RPGResourcesDebug bundle")
    func bundledPdfsArePresent() {
        let missing = PdfTagFixture.bundledExpectations.map(\.file).filter { PdfTagFixture.bundledPdfUrl(named: $0) == nil }

        #expect(missing.isEmpty, "Missing from TestPdfs: \(missing.joined(separator: ", "))")
        #expect(PdfTagFixture.bundled.count == PdfTagFixture.bundledExpectations.count)
    }

    @Test("Bundled PDFs open and have readable text", arguments: PdfTagFixture.bundled)
    func bundledPdfsAreReadable(_ fixture: PdfTagFixture) async throws {
        let document = try fixture.makeDocument()
        let pages = try await PdfPageTextReader.pages(of: .init(document: document), pageLimit: min(document.pageCount, 6))

        #expect(document.pageCount > 0)
        #expect(!pages.isEmpty, "\(fixture.name) has no extractable text")
    }

    @Test("Generated fixtures render PDFs the analyzer can read", arguments: PdfTagFixture.generated)
    func generatedFixturesAreReadable(_ fixture: PdfTagFixture) async throws {
        let document = try fixture.makeDocument()
        let pages = try await PdfPageTextReader.pages(of: .init(document: document), pageLimit: document.pageCount)

        #expect(document.pageCount >= 2)
        #expect(pages.count == document.pageCount)
        #expect(pages.allSatisfy { $0.text.count > 200 })
        #expect(!fixture.expectation.conceptGroups.isEmpty)
        #expect(fixture.expectation.requiredGroupCount >= 1)
    }

    @Test("No fixture requires and forbids the same term")
    func forbiddenTermsAreNotRequiredTerms() {
        for fixture in PdfTagFixture.generated + PdfTagFixture.bundled {
            let required = Set(fixture.expectation.conceptGroups.joined().map { $0.lowercased() })
            let forbidden = Set(fixture.expectation.forbiddenTerms.map { $0.lowercased() })

            #expect(required.isDisjoint(with: forbidden), "\(fixture.name) both requires and forbids a term")
        }
    }
}

#endif
