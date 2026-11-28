// @copyright André Trettin

#if !os(tvOS)

import Testing

@testable import GeneratorRPG

@Suite("Photo summary text format")
struct PhotoSummaryTextFormatTests {

    @Test("Reads the three labelled lines")
    func threeLines() throws {
        let analysis = try #require(PhotoSummaryTextFormat.analysis(from: """
        Title: Pirate in a Blue Coat
        Description: A bearded pirate in a blue coat holds a curved sabre.
        Tags: Character, pirate, sabre, tricorn hat
        """))

        #expect(analysis.title == "Pirate in a Blue Coat")
        #expect(analysis.summary == "A bearded pirate in a blue coat holds a curved sabre.")
        #expect(analysis.tags == ["Character", "pirate", "sabre", "tricorn hat"])
    }

    @Test("Accepts markdown, bullets, quotes and translated labels")
    func decoratedLines() throws {
        let analysis = try #require(PhotoSummaryTextFormat.analysis(from: """
        **Titel:** „Alter Seebär“
        - **Beschreibung:** Ein alter Seemann mit weißem Bart.
        - **Schlagwörter:** #Porträt; Seemann; Flasche.
        """))

        #expect(analysis.title == "Alter Seebär")
        #expect(analysis.summary == "Ein alter Seemann mit weißem Bart.")
        #expect(analysis.tags == ["Porträt", "Seemann", "Flasche"])
    }

    @Test("Joins a description wrapped over several lines")
    func wrappedDescription() throws {
        let analysis = try #require(PhotoSummaryTextFormat.analysis(from: """
        Title: Dwarf Scholar

        Description: A dwarf with round glasses.
        He carries a staff.
        Tags: Portrait, dwarf, glasses
        """))

        #expect(analysis.summary == "A dwarf with round glasses. He carries a staff.")
    }

    @Test("A refusal without description or tags is no analysis")
    func refusal() {
        #expect(PhotoSummaryTextFormat.analysis(from: "Sorry, I can't help with that.") == nil)
        #expect(PhotoSummaryTextFormat.analysis(from: "Title: Knight\nDescription: A knight.") == nil)
    }

    @Test("A colon inside the description does not start a new field")
    func colonInDescription() throws {
        let analysis = try #require(PhotoSummaryTextFormat.analysis(from: """
        Title: Map
        Description: A map with a legend: forest, river and town.
        Tags: Map, forest, river
        """))

        #expect(analysis.summary == "A map with a legend: forest, river and town.")
    }

    @Test("A tag that repeats a one-word title goes while enough tags remain")
    func tagRepeatingTitle() {
        #expect(PhotoSummaryAnalyzer.tags(["Magier", "Umhang", "Schnee", "Licht"], withoutTitle: "magier") == ["Umhang", "Schnee", "Licht"])
        #expect(PhotoSummaryAnalyzer.tags(["Pirat", "Mantel", "Hut"], withoutTitle: "Pirat") == ["Pirat", "Mantel", "Hut"])
        #expect(PhotoSummaryAnalyzer.tags(["Pirat", "Mantel", "Hut"], withoutTitle: "Pirat im Mantel") == ["Pirat", "Mantel", "Hut"])
    }

    @Test("A declined analysis may move to the cloud like a guardrail")
    func declinedFallsBack() {
        #expect(PhotoAnalysisFallbackPolicy.reason(forOnDeviceError: PhotoSummaryAnalysisError.declinedByModel) == .guardrail)
    }
}

#endif
