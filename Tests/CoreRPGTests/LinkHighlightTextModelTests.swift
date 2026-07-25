// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

struct LinkHighlightTextModelTests {
    @Test("Display content invalidates when search or source text changes")
    @MainActor
    func displayContentInvalidation() {
        // Given
        let sut = LinkHighlightTextModel(
            linkControllable: FakeLinkController.fake,
            text: "Zauber"
        )

        // When
        let initial = sut.displayText
        let cached = sut.displayText
        sut.reset(highlightedText: "za")
        let highlighted = sut.displayText
        sut.reset(highlightedText: "")
        sut.reset(text: "Magie")
        let updated = sut.displayText

        // Then
        #expect(initial.map(\.string) == ["Zauber"])
        #expect(cached.map(\.string) == ["Zauber"])
        #expect(highlighted.map(\.string) == ["Za", "uber"])
        #expect(updated.map(\.string) == ["Magie"])
    }

    @Test("Custom text renderer is reserved for links, expansion, and active search")
    @MainActor
    func customRendererEligibility() {
        // Given
        let sut = LinkHighlightTextModel(
            linkControllable: FakeLinkController.fake,
            text: "Ordinary character text"
        )

        // When / Then
        #expect(!sut.requiresCustomRenderer)

        sut.reset(highlightedText: "character")
        #expect(sut.requiresCustomRenderer)

        sut.reset(highlightedText: "")
        #expect(!sut.requiresCustomRenderer)

        sut.reset(
            text: "[Map](RPG://MAPS/0/84087225-BF5D-4398-B5F3-FDE0A0B79250)"
        )
        #expect(sut.requiresCustomRenderer)
    }

    @Test
    func parseLink() async throws {
        let text = "**4**: [Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)"
        
        let sut = await LinkHighlightTextModel(linkControllable: FakeLinkController.fake, text: text, highlightedText: "", toggler: { _, _, _ in })
        
        let result = await sut.displayText
        try #require(result.count == 5)
        #expect(result[0].string == "4")
        #expect(result[1].string == ": ")
        #expect(result[2].string == "tablecells.fill")
        #expect(result[3].string == "Dolch")
        #expect(result[4].string == " ")
    }
    
    @Test
    func parseLinkWithLink() async throws {
        let text = "**4**: [Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)➡️ [Show](RPG://TABLES/1/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show) Der Dolch ist schnell und leicht. Eine Ideale Waffen für den Dieb, aber macht auch nicht so viele Schadenspunkte.⬅️"
        
        let sut = await LinkHighlightTextModel(linkControllable: FakeLinkController.fake, text: text, highlightedText: "", toggler: { _, _, _ in })
        
        let result = await sut.displayText
        try #require(result.count == 11)
        print(result.map { $0.string })
        #expect(result[0].string == "4")
        #expect(result[1].string == ": ")
        #expect(result[2].string == "tablecells.fill")
        #expect(result[3].string == "Dolch")
        #expect(result[4].string == " ")
        #expect(result[5].string == "➡️")
        #expect(result[6].string == " ")
        #expect(result[7].string == "eye.fill")
        #expect(result[8].string == "Show")
        #expect(result[9].string == " ")
        #expect(result[10].string == " Der Dolch ist schnell und leicht. Eine Ideale Waffen für den Dieb, aber macht auch nicht so viele Schadenspunkte.")
    }

    @Test
    func hightLightAndBold() async throws {
        let text = "**Zauber**"

        let sut = await LinkHighlightTextModel(linkControllable: FakeLinkController.fake, text: text, highlightedText: "za")

        let result = await sut.displayText
        try #require(result.count == 2)
        #expect(result[0].string == "Za")
        #expect(result[1].string == "uber")
    }

    @Test
    func boldLinkWithLink() async throws {
        let text = "**[Alchemie](RPG://TABLES/0/613F90EF-B62D-4475-8FB4-48279148576F/6E45E610-2BD3-4088-98F5-FD62958E6452)➡️ [Show](RPG://TABLES/600/613F90EF-B62D-4475-8FB4-48279148576F/6E45E610-2BD3-4088-98F5-FD62958E6452/show) ZAW 1 (V), ERZ 10 (X): Dieses Talent wird benötigt, um magische Tränke zu brauen (siehe Seite 101). Jeder Talentrang reduziert die Zubereitungsdauer von Tränken und gibt +1 auf Proben, um diese herzustellen oder zu identifizieren (siehe Seite 47).⬅️**: 1 "

        let sut = await LinkHighlightTextModel(linkControllable: FakeLinkController.fake, text: text, highlightedText: "")

        let result = await sut.displayText
        print(result.count)
        print(result.map { $0.string })

        try #require(result.count == 10)
        #expect(result[0].string == "tablecells.fill")
        #expect(result[1].string == "Alchemie")
        #expect(result[2].string == " ")
        #expect(result[3].string == "➡️")
        #expect(result[4].string == " ")
        #expect(result[5].string == "eye.fill")
        #expect(result[6].string == "Show")
        #expect(result[7].string == " ")
        #expect(result[8].string == " ZAW 1 (V), ERZ 10 (X): Dieses Talent wird benötigt, um magische Tränke zu brauen (siehe Seite 101). Jeder Talentrang reduziert die Zubereitungsdauer von Tränken und gibt +1 auf Proben, um diese herzustellen oder zu identifizieren (siehe Seite 47).")
        #expect(result[9].string == ": 1 ")
    }

    @Test
    func manyLinksInLinks() async throws {
        let text = "[Feuerstrahl](RPG://VALUES/0/9C3B7278-2A0E-46B8-8A21-0E662D3C2A53/56124F38-7B74-41C6-B917-9B1AFB342A81)➡️ [Show](RPG://VALUES/600/9C3B7278-2A0E-46B8-8A21-0E662D3C2A53/56124F38-7B74-41C6-B917-9B1AFB342A81/show) [Zielzauber](RPG://VALUES/0/3C24A15D-E7C6-4105-805D-DDD5667D2581/A34D414F-AA1C-4528-9BC5-ED8E530E7098)➡️ [Show](RPG://VALUES/600/3C24A15D-E7C6-4105-805D-DDD5667D2581/A34D414F-AA1C-4528-9BC5-ED8E530E7098/show) [GEI](RPG://VALUES/0/A4749AC4-DCA2-437C-901E-145107ACE373/385DA33E-A366-4AA0-A98E-EFCB28BCEF5D)+ [GE](RPG://VALUES/0/A4749AC4-DCA2-437C-901E-145107ACE373/E1D0091E-DF46-40D8-9B79-FE071103B442)+[Zielzauber](RPG://VALUES/0/163E1240-53C6-4BC8-8DDC-CFCC874B76E3/E23237BB-D9C2-408D-B6C9-AFCF8DA149B6)-[PA gesamt](RPG://VALUES/0/323874A5-79F3-4705-B968-E05FB5863AFC/D4D799E7-1502-4E33-8452-09EF7E7C4AFB)⬅️+1+ [Zielzauber](RPG://VALUES/1/163E1240-53C6-4BC8-8DDC-CFCC874B76E3/E23237BB-D9C2-408D-B6C9-AFCF8DA149B6)+ [Feuermagier](RPG://VALUES/0/BFCFB9C5-D39E-495B-B11B-67F9FF1732D2/5D060124-4875-4ED9-B392-7B2A93508FA4)⬅️ = 17"

        let sut = await LinkHighlightTextModel(linkControllable: FakeLinkController.fake, text: text, highlightedText: "")

        let result = await sut.displayText
        try #require(result.count == 42)
        #expect(result[0].string == "list.bullet.rectangle")
        #expect(result[1].string == "Feuerstrahl")
        #expect(result[2].string == " ")
        #expect(result[3].string == "➡️")
        #expect(result[4].string == " ")
        #expect(result[5].string == "eye.fill")
        #expect(result[6].string == "Show")
        #expect(result[7].string == " ")
        #expect(result[8].string == " ")
        #expect(result[9].string == "list.bullet.rectangle")
        #expect(result[10].string == "Zielzauber")
        #expect(result[11].string == " ")
        #expect(result[12].string == "➡️")
        #expect(result[13].string == " ")
        #expect(result[14].string == "eye.fill")
        #expect(result[15].string == "Show")
        #expect(result[16].string == " ")
        #expect(result[17].string == " ")
        #expect(result[18].string == "list.bullet.rectangle")
        #expect(result[19].string == "GEI")
        #expect(result[20].string == " ")
        #expect(result[21].string == "+ ")
        #expect(result[22].string == "list.bullet.rectangle")
        #expect(result[23].string == "GE")
        #expect(result[24].string == " ")
        #expect(result[25].string == "+")
        #expect(result[26].string == "list.bullet.rectangle")
        #expect(result[27].string == "Zielzauber")
        #expect(result[28].string == " ")
        #expect(result[29].string == "-")
        #expect(result[30].string == "list.bullet.rectangle")
        #expect(result[31].string == "PA gesamt")
        #expect(result[32].string == " ")
        #expect(result[33].string == "+1+ ")
        #expect(result[34].string == "list.bullet.rectangle")
        #expect(result[35].string == "Zielzauber")
        #expect(result[36].string == " ")
        #expect(result[37].string == "+ ")
        #expect(result[38].string == "list.bullet.rectangle")
        #expect(result[39].string == "Feuermagier")
        #expect(result[40].string == " ")
        #expect(result[41].string == " = 17")
    }

    @Test @MainActor
    func duplicateLinkTogglerReceivesClickedOccurrence() async throws {
        let itemId = UUID()
        let firstLink = "[Orc](RPG://VALUES/0/\(itemId.uuidString))"
        let secondLink = "[Orc](RPG://VALUES/1/\(itemId.uuidString))"
        let links = LinkReplaceController.links(for: "\(firstLink) \(secondLink)")
        try #require(links.count == 2)

        let controller = TogglerCapturingLinkController(
            itemControllable: FakeItemController.fake
        )
        var toggledOccurrences: [Int] = []
        let sut = LinkHighlightTextModel(
            linkControllable: controller,
            text: "\(firstLink) \(secondLink)",
            toggler: { _, _, occurrence in
                toggledOccurrences.append(occurrence)
            }
        )

        sut.handle(link: links[1])
        let secondOccurrenceToggler = try #require(controller.capturedToggler)
        await secondOccurrenceToggler(itemId, .value)

        let showLink = try #require(
            LinkReplaceController.links(
                for: "[Show](RPG://VALUES/601/\(itemId.uuidString)/show)"
            ).first
        )
        sut.handle(link: showLink)
        let secondShowToggler = try #require(controller.capturedToggler)
        await secondShowToggler(itemId, .value)

        #expect(toggledOccurrences == [1, 1])
    }

}

private final class TogglerCapturingLinkController: LinkControllable, @unchecked Sendable {
    init(itemControllable: any ItemControllable) {
        self.itemControllable = itemControllable
    }

    let itemControllable: any ItemControllable
    @MainActor var capturedToggler: ((UUID, NetworkModules) async -> Void)?

    @MainActor
    func handleTextLink(
        url: URL,
        in text: String,
        shareResult: ShareValueResult?,
        toggler: ((UUID, NetworkModules) async -> Void)?,
        editAction: ((ItemRowModel) -> Bool)?
    ) -> String {
        capturedToggler = toggler
        return text
    }

    @MainActor
    func toggleTextLink(
        linkNumber: Int,
        itemId: UUID,
        entryId: UUID?,
        command: String?,
        in text: String,
        shareResult: ShareValueResult?,
        toggler: ((UUID, NetworkModules) async -> Void)?,
        editAction: ((ItemRowModel) -> Bool)?
    ) -> String {
        text
    }

    @MainActor
    func toggleLink(
        module: NetworkModules,
        linkNumber: Int,
        itemId: UUID,
        entryId: UUID?,
        command: String?
    ) -> String {
        ""
    }
}
