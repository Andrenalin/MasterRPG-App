// @copyright André Trettin

import Testing

@testable import CoreRPG

@MainActor
@Suite("Sheet search context")
struct SheetSearchContextTests {
    @Test("Query follows the currently attached result model")
    func queryFollowsActiveResults() {
        let context = SheetSearchContext(query: "Dragon")
        let firstResults = SheetRootModel.fake
        let secondResults = SheetRootModel.fake

        context.attachResults(firstResults)
        #expect(firstResults.searchText == "Dragon")

        context.attachResults(secondResults)
        context.query = "Goblin"

        #expect(firstResults.searchText == "Dragon")
        #expect(secondResults.searchText == "Goblin")

        // Detaching a stale view must not disconnect the active sheet.
        context.detachResults(firstResults)
        context.query = "Wizard"
        #expect(secondResults.searchText == "Wizard")

        context.detachResults(secondResults)
        context.query = "Rogue"
        #expect(secondResults.searchText == "Wizard")
    }
}
