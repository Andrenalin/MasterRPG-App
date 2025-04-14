// @copyright André Trettin

import Testing

@testable import AndrenalinKit
import Foundation

struct LinkReplaceControllerTests {
    @Test
    func parseLinkWithCommand() async throws {
        var text = " [Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)"
        
        var results = await LinkReplaceController.links(for: text)
        try #require(results.count == 1)
        #expect(results[0].name == "Show")
        #expect(results[0].module == NetworkModules.table)
        #expect(results[0].linkNumber == 600)
        #expect(results[0].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[0].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[0].command == LinkType.show.rawValue)
        #expect(results[0].markDown == "[Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)")
        
        text = " [Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/show)"
        
        results = await LinkReplaceController.links(for: text)
        try #require(results.count == 1)
        #expect(results[0].name == "Show")
        #expect(results[0].module == NetworkModules.table)
        #expect(results[0].linkNumber == 600)
        #expect(results[0].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[0].entryId == nil)
        #expect(results[0].command == LinkType.show.rawValue)
        #expect(results[0].markDown == "[Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/show)")
    }
    
    @Test
    func parseLinkWithLink() async throws {
        let text = "**4**: [Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)➡️ [Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show) Der Dolch ist schnell und leicht. Eine Ideale Waffen für den Dieb, aber macht auch nicht so viele Schadenspunkte.⬅️"
        
        var results = await LinkReplaceController.links(for: text)
        try #require(results.count == 2)
        results = results.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
        
        #expect(results[0].name == "Dolch")
        #expect(results[0].module == NetworkModules.table)
        #expect(results[0].linkNumber == 0)
        #expect(results[0].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[0].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[0].command == nil)
        #expect(results[0].markDown == "[Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)")
        
        #expect(results[1].name == "Show")
        #expect(results[1].module == NetworkModules.table)
        #expect(results[1].linkNumber == 600)
        #expect(results[1].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[1].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[1].command == "show")
        #expect(results[1].markDown == "[Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)")
    }
    
    @Test
    func parseLinksWithManyCommands() async throws {
        let text = "**4**: [Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)➡️ [Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)  [Share](RPG://TABLES/500/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/share)[Remove](RPG://TABLES/300/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/remove)Der Dolch ist schnell und leicht. Eine Ideale Waffen für den Dieb, aber macht auch nicht so viele Schadenspunkte.⬅️ [Dolch](RPG://TABLES/1/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)➡️[Play](RPG://TABLES/201/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/play)[Show](RPG://TABLES/601/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)  [Share](RPG://TABLES/501/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/share)[Remove](RPG://TABLES/301/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/remove) Some more Text⬅️"
        
        var results = await LinkReplaceController.links(for: text)
        results = results.sorted { $0.range.lowerBound < $1.range.lowerBound }
        
        try #require(results.count == 9)
        #expect(results[0].name == "Dolch")
        #expect(results[0].module == NetworkModules.table)
        #expect(results[0].linkNumber == 0)
        #expect(results[0].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[0].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[0].markDown == "[Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)")
        
        #expect(results[1].name == "Show")
        #expect(results[1].module == NetworkModules.table)
        #expect(results[1].linkNumber == 600)
        #expect(results[1].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[1].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[1].markDown == "[Show](RPG://TABLES/600/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)")
        
        #expect(results[2].name == "Share")
        #expect(results[2].module == NetworkModules.table)
        #expect(results[2].linkNumber == 500)
        #expect(results[2].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[2].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[2].markDown == "[Share](RPG://TABLES/500/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/share)")
        
        #expect(results[3].name == "Remove")
        #expect(results[3].module == NetworkModules.table)
        #expect(results[3].linkNumber == 300)
        #expect(results[3].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[3].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[3].markDown == "[Remove](RPG://TABLES/300/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/remove)")
        
        #expect(results[5].name == "Play")
        #expect(results[5].module == NetworkModules.table)
        #expect(results[5].linkNumber == 201)
        #expect(results[5].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[5].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[5].markDown == "[Play](RPG://TABLES/201/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/play)")
        
        #expect(results[6].name == "Show")
        #expect(results[6].module == NetworkModules.table)
        #expect(results[6].linkNumber == 601)
        #expect(results[6].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[6].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[6].markDown == "[Show](RPG://TABLES/601/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/show)")
        
        #expect(results[7].name == "Share")
        #expect(results[7].module == NetworkModules.table)
        #expect(results[7].linkNumber == 501)
        #expect(results[7].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[7].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[7].markDown == "[Share](RPG://TABLES/501/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/share)")
        
        #expect(results[8].name == "Remove")
        #expect(results[8].module == NetworkModules.table)
        #expect(results[8].linkNumber == 301)
        #expect(results[8].itemId == UUID(uuidString: "84087225-BF5D-4398-B5F3-FDE0A0B79250")!)
        #expect(results[8].entryId == UUID(uuidString: "EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!)
        #expect(results[8].markDown == "[Remove](RPG://TABLES/301/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1/remove)")
    }
    
    @Test
    func parseAndRepairText() async throws {
        let text = "[Feuerstrahl](RPG://VALUES/0/9C3B7278-2A0E-46B8-8A21-0E662D3C2A53/56124F38-7B74-41C6-B917-9B1AFB342A81)➡️ [Show](RPG://VALUES/600/9C3B7278-2A0E-46B8-8A21-0E662D3C2A53/56124F38-7B74-41C6-B917-9B1AFB342A81/show) [Zielzauber](RPG://VALUES/0/3C24A15D-E7C6-4105-805D-DDD5667D2581/A34D414F-AA1C-4528-9BC5-ED8E530E7098)➡️ [Show](RPG://VALUES/600/3C24A15D-E7C6-4105-805D-DDD5667D2581/A34D414F-AA1C-4528-9BC5-ED8E530E7098/show) [GEI](RPG://VALUES/0/A4749AC4-DCA2-437C-901E-145107ACE373/385DA33E-A366-4AA0-A98E-EFCB28BCEF5D)+ [GE](RPG://VALUES/0/A4749AC4-DCA2-437C-901E-145107ACE373/E1D0091E-DF46-40D8-9B79-FE071103B442)+[Zielzauber](RPG://VALUES/0/163E1240-53C6-4BC8-8DDC-CFCC874B76E3/E23237BB-D9C2-408D-B6C9-AFCF8DA149B6)-[PA gesamt](RPG://VALUES/0/323874A5-79F3-4705-B968-E05FB5863AFC/D4D799E7-1502-4E33-8452-09EF7E7C4AFB)⬅️+1+ [Zielzauber](RPG://VALUES/0/163E1240-53C6-4BC8-8DDC-CFCC874B76E3/E23237BB-D9C2-408D-B6C9-AFCF8DA149B6)+ [Feuermagier](RPG://VALUES/0/BFCFB9C5-D39E-495B-B11B-67F9FF1732D2/5D060124-4875-4ED9-B392-7B2A93508FA4)⬅️ = 17"
        
        var resultText = text
        let _ = await LinkReplaceController.linksRepair(for: &resultText)
        #expect(resultText != text)
        
        let expText = "[Feuerstrahl](RPG://VALUES/0/9C3B7278-2A0E-46B8-8A21-0E662D3C2A53/56124F38-7B74-41C6-B917-9B1AFB342A81)➡️ [Show](RPG://VALUES/600/9C3B7278-2A0E-46B8-8A21-0E662D3C2A53/56124F38-7B74-41C6-B917-9B1AFB342A81/show) [Zielzauber](RPG://VALUES/0/3C24A15D-E7C6-4105-805D-DDD5667D2581/A34D414F-AA1C-4528-9BC5-ED8E530E7098)➡️ [Show](RPG://VALUES/600/3C24A15D-E7C6-4105-805D-DDD5667D2581/A34D414F-AA1C-4528-9BC5-ED8E530E7098/show) [GEI](RPG://VALUES/0/A4749AC4-DCA2-437C-901E-145107ACE373/385DA33E-A366-4AA0-A98E-EFCB28BCEF5D)+ [GE](RPG://VALUES/0/A4749AC4-DCA2-437C-901E-145107ACE373/E1D0091E-DF46-40D8-9B79-FE071103B442)+[Zielzauber](RPG://VALUES/0/163E1240-53C6-4BC8-8DDC-CFCC874B76E3/E23237BB-D9C2-408D-B6C9-AFCF8DA149B6)-[PA gesamt](RPG://VALUES/0/323874A5-79F3-4705-B968-E05FB5863AFC/D4D799E7-1502-4E33-8452-09EF7E7C4AFB)⬅️+1+ [Zielzauber](RPG://VALUES/1/163E1240-53C6-4BC8-8DDC-CFCC874B76E3/E23237BB-D9C2-408D-B6C9-AFCF8DA149B6)+ [Feuermagier](RPG://VALUES/0/BFCFB9C5-D39E-495B-B11B-67F9FF1732D2/5D060124-4875-4ED9-B392-7B2A93508FA4)⬅️ = 17"
        
        #expect(resultText == expText)
    }
}
