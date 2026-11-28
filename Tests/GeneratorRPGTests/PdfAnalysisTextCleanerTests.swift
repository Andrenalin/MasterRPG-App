// @copyright André Trettin

#if !os(tvOS)

import Foundation
import Testing

@testable import GeneratorRPG

@Suite("PDF analysis text cleaner")
struct PdfAnalysisTextCleanerTests {
    @Test("Object replacement characters and soft hyphens are removed")
    func invisibleCharactersAreRemoved() {
        let text = "\u{FFFC}\n\u{FFFC}\nei\u{00AD}nem Säurebad\n\u{FFFC}"

        #expect(PdfAnalysisTextCleaner.cleaned(text) == "einem Säurebad")
    }

    @Test("A word split by a line-break hyphen is joined when the next line starts lowercase")
    func lineBreakHyphenationIsJoined() {
        let text = "Valen Coladris ist die einzige Stadt auf der gleichnami-\ngen Insel."

        #expect(PdfAnalysisTextCleaner.cleaned(text) == "Valen Coladris ist die einzige Stadt auf der gleichnamigen Insel.")
    }

    @Test("Hyphens before a capitalized word or a conjunction stay")
    func meaningfulHyphensStay() {
        #expect(PdfAnalysisTextCleaner.cleaned("Rhein-\nRuhr") == "Rhein-\nRuhr")
        #expect(PdfAnalysisTextCleaner.cleaned("Kultur-\nund Klassenbonus") == "Kultur- und Klassenbonus")
    }

    @Test("Lines without letters are dropped, blank lines and whitespace collapse")
    func numberGridsAndWhitespaceCollapse() {
        let text = """
        Name   Botho\tPhillip
        01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19
        50 25
        —


        Beruf
        3
        """

        #expect(PdfAnalysisTextCleaner.cleaned(text) == "Name Botho Phillip\n\nBeruf")
    }

    @Test("Dot leaders of a table of contents become one space")
    func dotLeadersCollapse() {
        #expect(PdfAnalysisTextCleaner.cleaned("Strassenwaise......48\nDorf. 44") == "Strassenwaise 48\nDorf. 44")
    }

    @Test("Text of only noise is empty")
    func noiseOnlyIsEmpty() {
        #expect(PdfAnalysisTextCleaner.cleaned("\u{FFFC}\n12\n\n—\n").isEmpty)
    }

    @Test("Imprint and license pages are boilerplate")
    func imprintPagesAreBoilerplate() {
        let imprint = """
        IMPRESSUM
        Autor:
        Stefan Bushuven
        Herausgeber:
        Patric Götz
        Lektorat:
        Falk Glade
        Copyright © 2013 by Stefan Bushuven.
        Alle Rechte vorbehalten.
        """
        let license = """
        DIE GS-LIZENZ
        Die Texte stehen unter folgender Creative
        Common Lizenz: http://creativecommons.org/licenses/by-nc-sa/3.0/de/
        """

        #expect(PdfAnalysisTextCleaner.isBoilerplate(imprint))
        #expect(PdfAnalysisTextCleaner.isBoilerplate(license))
    }

    @Test("A long content page with a credits footer is not boilerplate")
    func contentPageWithCreditsIsKept() {
        let story = String(repeating: "Die Sturmelfen bewohnen die Insel der Stürme und beten zu Hefrach. ", count: 40)
        let page = story + "\nAbbildung unter CC BY-ND 3.0 (https://creativecommons.org/licenses/by-nd/3.0/).\nLektorat: Blakharaz"

        #expect(!PdfAnalysisTextCleaner.isBoilerplate(page))
        #expect(!PdfAnalysisTextCleaner.isBoilerplate("Ein Abenteuer für die Stufen 1-4 von Autor: Max"))
    }

    @Test("Boilerplate pages are skipped only when the document has other pages")
    func boilerplatePagesAreSkippedWhenContentExists() {
        let imprint = PdfPageTextReader.Page(pageNumber: 2, text: "Impressum", isBoilerplate: true)
        let content = PdfPageTextReader.Page(pageNumber: 5, text: "Endzeit", isBoilerplate: false)

        #expect(PdfAnalysisTextCleaner.contentPages([imprint, content]).map(\.pageNumber) == [5])
        #expect(PdfAnalysisTextCleaner.contentPages([imprint]).map(\.pageNumber) == [2])
    }
}

#endif
