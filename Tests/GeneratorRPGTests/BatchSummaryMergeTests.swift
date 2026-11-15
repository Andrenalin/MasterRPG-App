// @copyright André Trettin

#if !os(tvOS)

import Testing

@testable import GeneratorRPG

@Suite("Batch summary merge")
struct BatchSummaryMergeTests {
    @Test("An empty description takes the generated text")
    func emptyDescriptionTakesGenerated() {
        #expect(BatchSummaryMerge.description(existing: "  ", generated: "A cave.") == "A cave.")
    }

    @Test("A written description gets the generated text appended")
    func appendsToWritten() {
        #expect(BatchSummaryMerge.description(existing: "Mine.", generated: "A cave.") == "Mine.\n\nA cave.")
    }

    @Test("Running the batch twice does not duplicate the paragraph")
    func secondRunIsIdempotent() {
        let first = BatchSummaryMerge.description(existing: "Mine.", generated: "A cave.")
        let second = BatchSummaryMerge.description(existing: first, generated: "A cave.")

        #expect(second == first)
    }

    @Test("Curated tags stay and generated tags join without duplicates")
    func tagsAreMerged() {
        let tags = BatchSummaryMerge.tags(existing: ["Boss", "Cave"], generated: ["cave", "Dark"])

        #expect(tags == ["Boss", "Cave", "Dark"])
    }
}

#endif
