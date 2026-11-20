//
//  GeneratorRPGTests.swift
//  GeneratorRPGTests
//
//  Created by Andre Trettin on 2/10/2568 BE.
//

import Testing
@testable import GeneratorRPG

@MainActor
struct GeneratorRPGTests {

    @Test func limitedTextAddsMarkerWithinBudget() {
        let result = FoundationModelInputLimiter.limitedText(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            maxCharacters: 32
        )

        #expect(result.count == 32)
        #expect(result.hasSuffix(FoundationModelInputLimiter.truncationMarker))
    }

    @Test func limitedTextShrinksTheBudgetForTokenDenseScripts() {
        let latin = String(repeating: "a", count: 4_000)
        let japanese = String(repeating: "魔", count: 4_000)

        let latinResult = FoundationModelInputLimiter.limitedText(latin, maxCharacters: 3_000)
        let japaneseResult = FoundationModelInputLimiter.limitedText(japanese, maxCharacters: 3_000)

        #expect(latinResult.count == 3_000, "Latin text keeps the full character budget")
        #expect(japaneseResult.count == 1_000, "one token per character: a third of the budget")
        #expect(japaneseResult.hasSuffix(FoundationModelInputLimiter.truncationMarker))
    }

    @Test func combinedTextShrinksTheBudgetForTokenDenseScripts() {
        let result = FoundationModelInputLimiter.limitedCombinedText(
            pages: [(pageNumber: 1, text: String(repeating: "魔", count: 4_000))],
            maxPages: 5,
            maxCharacters: 3_000
        )

        #expect(result.count == 1_000)
    }

    @Test func combinedTextHonorsPageAndCharacterLimits() {
        let result = FoundationModelInputLimiter.limitedCombinedText(
            pages: ["first", "second", "third"],
            maxPages: 2,
            maxCharacters: 1_000
        )

        #expect(result.contains("--- Page 1 ---"))
        #expect(result.contains("--- Page 2 ---"))
        #expect(!result.contains("--- Page 3 ---"))
        #expect(result.contains("first"))
        #expect(result.contains("second"))
    }

    @Test func pageTextsHonorPerPageLimit() {
        let result = FoundationModelInputLimiter.limitedPageTexts(
            pages: ["abcdefghijklmno", "", "pqrstuvwxyz"],
            maxPages: 3,
            maxCharactersPerPage: 10
        )

        #expect(result.count == 2)
        #expect(result[0].pageNumber == 1)
        #expect(result[0].text.count == 10)
        #expect(result[0].wasTruncated)
        #expect(result[1].pageNumber == 3)
        #expect(result[1].wasTruncated)
    }

}
