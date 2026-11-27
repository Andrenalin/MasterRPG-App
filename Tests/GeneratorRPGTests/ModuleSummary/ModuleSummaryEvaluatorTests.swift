// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

/// The adventure and map rules and the fixtures themselves. These need no Apple Intelligence and run
/// in every test run, so a broken evaluation is found before it judges the model.
@Suite("Adventure and map summary evaluator")
struct ModuleSummaryEvaluatorTests {
    private let expectation = TableSummaryExpectation(
        tags: PdfTagExpectation(conceptGroups: [["crypt", "tomb"], ["undead"]], minimumMatchedGroups: 1),
        titleConcepts: [["crypt", "tomb"]],
        descriptionConcepts: [["crypt", "undead"]]
    )

    private func evaluate(_ kind: ModuleSummaryKind, title: String = "Chapel Crypt", tags: [String]? = nil) -> TableSummaryVerdict {
        TableSummaryEvaluator.forModule(kind).evaluate(
            title: title,
            description: "A crypt full of undead beneath a ruined chapel.",
            tags: tags ?? ["Crypt", "Undead", "Chapel"],
            expectation: expectation
        )
    }

    @Test("A good summary passes for both modules", arguments: ModuleSummaryKind.allCases)
    func goodSummary(kind: ModuleSummaryKind) {
        #expect(evaluate(kind).passed)
    }

    @Test("A map title that only names the form fails", arguments: ["Map", "Dungeon Map", "Karte", "Map: Crypt", "Räume"])
    func genericMapTitle(title: String) {
        #expect(!evaluate(.map, title: title).titleRuleViolations.isEmpty)
    }

    @Test("An adventure title that only names the form fails", arguments: ["Adventure", "Abenteuer", "Adventure: Crypt", "Szenario"])
    func genericAdventureTitle(title: String) {
        #expect(!evaluate(.adventure, title: title).titleRuleViolations.isEmpty)
    }

    @Test("Form words are generic tags for their module", arguments: [
        (ModuleSummaryKind.map, "Map"), (.map, "Rooms"), (.map, "Karte"),
        (.adventure, "Adventure"), (.adventure, "Kampagne"), (.adventure, "Scenario")
    ])
    func genericModuleTag(kind: ModuleSummaryKind, tag: String) {
        let result = evaluate(kind, tags: ["Crypt", "Undead", tag])

        #expect(!result.tagRuleViolations.isEmpty, "'\(tag)' should be generic for \(kind)")
    }

    @Test("The table's generic words still apply")
    func tableRulesStillApply() {
        #expect(!evaluate(.map, title: "Table: Crypt").titleRuleViolations.isEmpty)
        #expect(!evaluate(.adventure, tags: ["Crypt", "Undead", "RPG"]).tagRuleViolations.isEmpty)
    }

    @Test("A description that calls the item a table fails", arguments: [
        (ModuleSummaryKind.map, "This table lists the rooms of a crypt full of undead."),
        (.adventure, "Diese Tabelle beschreibt eine Gruft voller Untoter in der Krypta."),
        (.adventure, "The crypt holds undead; roll on the tables below.")
    ])
    func descriptionCallsItemATable(kind: ModuleSummaryKind, description: String) {
        let result = TableSummaryEvaluator.forModule(kind).evaluate(
            title: "Chapel Crypt",
            description: description,
            tags: ["Crypt", "Undead", "Chapel"],
            expectation: expectation
        )

        #expect(result.descriptionRuleViolations.contains { $0.hasPrefix("calls the item a ") })
    }

    @Test("Table words inside other words and table summaries are fine")
    func tableWordsElsewhere() {
        let stable = TableSummaryEvaluator.forModule(.map).evaluate(
            title: "Chapel Crypt",
            description: "A crypt of undead beneath a chapel with a stable and a timetable of rites.",
            tags: ["Crypt", "Undead", "Chapel"],
            expectation: expectation
        )
        let table = TableSummaryEvaluator().evaluate(
            title: "Chapel Crypt",
            description: "This table lists the undead of a crypt.",
            tags: ["Crypt", "Undead", "Chapel"],
            expectation: expectation
        )

        #expect(stable.descriptionRuleViolations.isEmpty)
        #expect(table.descriptionRuleViolations.isEmpty)
    }

    // MARK: - Fixtures

    static let allFixtures = ModuleSummaryKind.allCases.flatMap { ModuleSummaryFixture.all(for: $0) }

    @Test("Every fixture is usable", arguments: allFixtures)
    func fixtureIsUsable(fixture: ModuleSummaryFixture) {
        #expect(fixture.entries.count >= 6)
        #expect(fixture.entries.allSatisfy { !$0.name.isEmpty })
        #expect(!fixture.expectation.titleConcepts.isEmpty)
        #expect(!fixture.expectation.descriptionConcepts.isEmpty)
        #expect(fixture.expectation.tags.requiredGroupCount > 0)
        #expect(fixture.expectation.tags.forbiddenTerms.isEmpty, "forbidden terms belong to TableSummaryExpectation")
        // The analyzer cuts the text at 7,000 characters; the fixtures must fit so they are judged whole.
        #expect(fixture.entriesText.count < 7000)
        // Links are reduced to their labels like compactText(for:) does.
        #expect(!fixture.entriesText.contains("rpg://"))
    }

    @Test("A named fixture passes its name like compactText(for:)")
    func entriesTextShape() {
        #expect(ModuleSummaryFixture.blackwaterKeep.entriesText.hasPrefix("Map: Blackwater Keep\n\n- Gatehouse: "))
        #expect(ModuleSummaryFixture.glassOrchidHeist.entriesText.hasPrefix("Adventure: Operation Glass Orchid\n\n- Briefing: Fixer Ines Varga offers"))
        #expect(ModuleSummaryFixture.chapelCrypt.entriesText.hasPrefix("- 1 Entrance stairs: "))
        #expect(ModuleSummaryFixture.sewerNamesOnly.entriesText.contains("\n\n- 1 Storm drain outlet\n- 2 Overflow cistern"))
    }

    @Test("A map's photo description and tags come before the rooms")
    func mapPhotoText() {
        let text = ModuleSummaryFixture.sewerNamesOnly.entriesText

        #expect(text.hasPrefix("Map photo: Hand-drawn map of brick sewer tunnels"))
        #expect(text.contains("\nMap photo tags: Sewer, Tunnels, Underground, City\n\n- 1 Storm drain outlet\n"))
        #expect(text.hasSuffix("- 6 Thieves' guild door"))
        #expect(!ModuleSummaryFixture.chapelCrypt.entriesText.contains("Map photo"))
        #expect(ModuleSummaryFixture.adventures.allSatisfy { $0.photoDescription.isEmpty && $0.photoTags.isEmpty })
    }

    @Test("A long map photo description is cut, empty photo tags are left out")
    func mapPhotoBounds() {
        let text = TextSummaryExtractionFormatter.formatMap(
            title: "Map",
            name: "",
            entries: [("Hall", "A [statue](rpg://CHARACTER/1/00000000-0000-0000-0000-000000000001) stands here.")],
            photoDescription: String(repeating: "a", count: 2000),
            photoTags: [" ", ""]
        )

        #expect(text == "Map photo: " + String(repeating: "a", count: TextSummaryExtractionFormatter.maximumPhotoDescriptionLength) + "\n\n- Hall: A statue stands here.")
    }

    @Test("Fixtures belong to their module and names are unique", arguments: ModuleSummaryKind.allCases)
    func fixturesPerModule(kind: ModuleSummaryKind) {
        let fixtures = ModuleSummaryFixture.all(for: kind)
        let names = fixtures.map(\.name)

        #expect(fixtures.count >= 4)
        #expect(fixtures.allSatisfy { $0.kind == kind })
        #expect(Set(names).count == names.count)
    }

    @Test("Language fixtures forbid words of the other language", arguments: allFixtures)
    func languageFixturesForbidOtherLanguage(fixture: ModuleSummaryFixture) {
        let germanInput = fixture.name.contains("German entries")
        if fixture.outputLanguage == "German" || germanInput {
            #expect(!fixture.expectation.forbiddenTerms.isEmpty)
        }
    }

    @Test("The sample dataset repeats every fixture once per run", arguments: ModuleSummaryKind.allCases)
    func datasetSize(kind: ModuleSummaryKind) {
        #expect(ModuleSummarySample.dataset(for: kind, runs: 3).count == ModuleSummaryFixture.all(for: kind).count * 3)
    }
}

#endif
