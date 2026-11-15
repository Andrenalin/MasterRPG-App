// @copyright André Trettin

#if !os(tvOS)

import Testing

@testable import GeneratorRPG

/// CODE_AUDIT_26 §6.9: the batch fills an empty name and adds tags, nothing else.
@Suite("Batch summary merge")
struct BatchSummaryMergeTests {
    @Test("An empty name takes the generated title, a set name is kept")
    func nameIsFilledOnlyWhenEmpty() {
        let filled = BatchSummaryMerge.change(existingName: "  ", existingTags: [], generatedTitle: " Cave Loot ", generatedTags: [])
        let kept = BatchSummaryMerge.change(existingName: "Mine", existingTags: [], generatedTitle: "Cave Loot", generatedTags: [])

        #expect(filled.name == "Cave Loot")
        #expect(kept.name == nil)
        #expect(kept.isEmpty)
    }

    @Test("Curated tags stay and generated tags join without duplicates")
    func tagsAreMerged() {
        let change = BatchSummaryMerge.change(
            existingName: "Mine",
            existingTags: ["Boss", "Cave"],
            generatedTitle: "",
            generatedTags: ["cave", "Dark"]
        )

        #expect(change.tags == ["Boss", "Cave", "Dark"])
        #expect(change.addedTagCount == 1)
    }

    @Test("Running the batch twice changes nothing the second time")
    func secondRunIsIdempotent() throws {
        let first = BatchSummaryMerge.change(existingName: "", existingTags: [], generatedTitle: "Loot", generatedTags: ["Gold"])
        let second = BatchSummaryMerge.change(
            existingName: try #require(first.name),
            existingTags: try #require(first.tags),
            generatedTitle: "Loot",
            generatedTags: ["Gold"]
        )

        #expect(second.isEmpty)
    }

    @Test("Model output is bounded: oversized titles, empty or long tags and extra tags are cut")
    func outputIsBounded() {
        let long = String(repeating: "x", count: BatchSummaryMerge.maximumTagLength + 1)
        let many = (0..<20).map { "tag\($0)" }
        let change = BatchSummaryMerge.change(
            existingName: "",
            existingTags: [],
            generatedTitle: String(repeating: "T", count: 500),
            generatedTags: ["", "  ", long] + many
        )

        #expect(change.name?.count == BatchSummaryMerge.maximumTitleLength)
        #expect(change.tags?.count == BatchSummaryMerge.maximumGeneratedTags)
        #expect(change.tags?.contains(long) == false)
    }
}

#endif
