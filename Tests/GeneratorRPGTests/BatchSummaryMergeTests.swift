// @copyright André Trettin

#if !os(tvOS)

import Testing

@testable import GeneratorRPG

/// The batch fills an empty name and replaces description and tags with the generated ones.
/// CODE_AUDIT_26 §6.9 bounded the output; the replacement of description and tags is the
/// person's decision of 2026-11-24 (the dialog says so before Start).
@Suite("Batch summary merge")
struct BatchSummaryMergeTests {
    private func change(
        name: String = "Mine",
        description: String = "Old text",
        tags: [String] = ["Old"],
        title: String = "Cave Loot",
        generatedDescription: String = "Loot found in a cave.",
        generatedTags: [String] = ["Cave", "Loot", "Gold"]
    ) -> BatchSummaryMerge.Change {
        BatchSummaryMerge.change(
            existingName: name,
            existingDescription: description,
            existingTags: tags,
            generatedTitle: title,
            generatedDescription: generatedDescription,
            generatedTags: generatedTags
        )
    }

    @Test("An empty name takes the generated title, a set name is kept")
    func nameIsFilledOnlyWhenEmpty() {
        #expect(change(name: "  ", title: " Cave Loot ").name == "Cave Loot")
        #expect(change(name: "Mine").name == nil)
    }

    @Test("The generated description replaces the existing one")
    func descriptionIsReplaced() {
        #expect(change(description: "Old text", generatedDescription: " Loot found in a cave. ").description == "Loot found in a cave.")
        #expect(change(description: "").description == "Loot found in a cave.")
    }

    @Test("The generated tags replace the existing ones, curated tags do not stay")
    func tagsAreReplaced() {
        let result = change(tags: ["Boss", "Cave"], generatedTags: ["Dark", "Loot", "Gold"])

        #expect(result.tags == ["Dark", "Loot", "Gold"])
    }

    @Test("Label tags are cut to their value and repeats go")
    func labelsAreCut() {
        let result = change(generatedTags: ["Ausruestung: Trading", "Gueter: Lebensmittel", "trading", "Handel"])

        #expect(result.tags == ["Trading", "Lebensmittel", "Handel"])
    }

    @Test("Nothing is erased: an empty generated description or tag list keeps the item")
    func emptyOutputKeepsItem() {
        let result = change(generatedDescription: "  ", generatedTags: ["", "  "])

        #expect(result.description == nil)
        #expect(result.tags == nil)
        #expect(result.isEmpty)
    }

    @Test("Running the batch twice changes nothing the second time")
    func secondRunIsIdempotent() throws {
        let first = change(name: "", description: "", tags: [])
        let second = change(
            name: try #require(first.name),
            description: try #require(first.description),
            tags: try #require(first.tags)
        )

        #expect(second.isEmpty)
    }

    @Test("The same tags in another order are no change")
    func tagOrderIsNoChange() {
        #expect(change(tags: ["Gold", "Cave", "Loot"]).tags == nil)
    }

    @Test("Model output is bounded: oversized title and description, long tags and extra tags are cut")
    func outputIsBounded() {
        let long = String(repeating: "x", count: BatchSummaryMerge.maximumTagLength + 1)
        let many = (0..<20).map { "tag\($0)" }
        let result = change(
            name: "",
            title: String(repeating: "T", count: 500),
            generatedDescription: String(repeating: "D", count: 2000),
            generatedTags: [long] + many
        )

        #expect(result.name?.count == BatchSummaryMerge.maximumTitleLength)
        #expect(result.description?.count == BatchSummaryMerge.maximumDescriptionLength)
        #expect(result.tags?.count == BatchSummaryMerge.maximumGeneratedTags)
        #expect(BatchSummaryMerge.maximumGeneratedTags == 5)
    }
}

#endif
