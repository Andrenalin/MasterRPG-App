// Example: Cross-Module Search Test
// This demonstrates how the cross-module search works

import Testing
import Foundation

@Suite("Cross-Module Search Tests")
struct CrossModuleSearchTests {
    
    @Test("Search finds match in linked Map from Adventure")
    func searchAcrossModules() async throws {
        // GIVEN: An Adventure item with a link to a Map
        let adventureItem = MockItem(
            id: UUID(),
            name: "The Tavern Quest",
            description: "Visit the local tavern",
            entries: [
                MockEntry(
                    id: UUID(),
                    name: "Tavern",
                    content: "The tavern is detailed in [Tavern Floor Plan](adr://map/\(mapItemId.uuidString)/0)"
                )
            ]
        )
        
        let mapItemId = UUID()
        let bathroomEntryId = UUID()
        
        let mapItem = MockItem(
            id: mapItemId,
            name: "Tavern Floor Plan",
            description: "Detailed floor plan of the tavern",
            entries: [
                MockEntry(id: UUID(), name: "Kitchen", content: "The cooking area"),
                MockEntry(id: bathroomEntryId, name: "Bathroom", content: "Facilities for patrons"),
                MockEntry(id: UUID(), name: "Storage", content: "Barrels and supplies")
            ]
        )
        
        // WHEN: Searching for "Bathroom" in the Adventure module
        let searchText = "Bathroom"
        let result = await adventureSearchControllable.searchInSheet(
            itemId: adventureItem.id,
            searchText: searchText,
            includeLinks: true,
            rootManager: mockRootManager
        )
        
        // THEN: Should find the Tavern entry (because it links to a map with "Bathroom")
        #expect(result.matchedEntries.count == 1)
        
        let match = try #require(result.matchedEntries.first)
        #expect(match.entryName == "Tavern")
        
        // AND: Should have a link match location pointing to the map
        let linkMatch = try #require(
            match.matchLocations.first { 
                if case .link(let itemId, let module) = $0,
                   itemId == mapItemId,
                   module == .map {
                    return true
                }
                return false
            }
        )
        
        // AND: Should have cross-module match information
        let crossMatch = try #require(result.crossModuleMatches[match.entryId]?.first)
        #expect(crossMatch.linkedItemId == mapItemId)
        #expect(crossMatch.linkedModule == .map)
        #expect(crossMatch.matchedEntryIds.contains(bathroomEntryId))
        
        // AND: Should auto-expand the link
        #expect(result.expandedLinks[match.entryId]?.contains(mapItemId) == true)
    }
    
    @Test("Search prioritizes same-module matches over cross-module")
    func relevanceScoring() async throws {
        // GIVEN: Two entries - one with direct match, one with cross-module match
        let adventureItem = MockItem(
            id: UUID(),
            name: "Quest Log",
            description: "Track your quests",
            entries: [
                // Direct match in Adventure module
                MockEntry(
                    id: UUID(),
                    name: "Bathroom Key Quest",
                    content: "Find the bathroom key"
                ),
                // Cross-module match (links to Map)
                MockEntry(
                    id: UUID(),
                    name: "Tavern Quest",
                    content: "Visit [Tavern Floor Plan](adr://map/\(mapItemId.uuidString)/0)"
                )
            ]
        )
        
        let mapItemId = UUID()
        let mapItem = MockItem(
            id: mapItemId,
            name: "Tavern Floor Plan",
            entries: [
                MockEntry(id: UUID(), name: "Bathroom", content: "The facilities")
            ]
        )
        
        // WHEN: Searching for "Bathroom"
        let result = await adventureSearchControllable.searchInSheet(
            itemId: adventureItem.id,
            searchText: "Bathroom",
            includeLinks: true,
            rootManager: mockRootManager
        )
        
        // THEN: Both entries should be found
        #expect(result.matchedEntries.count == 2)
        
        // AND: Direct match should have higher relevance than cross-module
        let directMatch = try #require(result.matchedEntries.first { $0.entryName.contains("Key") })
        let crossMatch = try #require(result.matchedEntries.first { $0.entryName.contains("Tavern") })
        
        #expect(directMatch.relevanceScore > crossMatch.relevanceScore)
        
        // AND: Direct match should be .name, cross-module should be .link
        let hasNameMatch = directMatch.matchLocations.contains { 
            if case .name = $0 { return true }
            return false
        }
        #expect(hasNameMatch == true)
        
        let hasLinkMatch = crossMatch.matchLocations.contains {
            if case .link = $0 { return true }
            return false
        }
        #expect(hasLinkMatch == true)
    }
    
    @Test("TableSheetModel expands links with correct module")
    func tableSheetModelExpansion() async throws {
        // GIVEN: A TableSheetModel with cross-module search results
        let mapItemId = UUID()
        let tavernEntryId = UUID()
        
        let linkControllable = MockLinkControllable(rootManager: mockRootManager)
        let adventureModel = MockItem(
            id: UUID(),
            entries: [
                MockEntry(
                    id: tavernEntryId,
                    name: "Tavern",
                    content: "[Map](adr://map/\(mapItemId.uuidString)/0)"
                )
            ]
        )
        
        let tableSheetModel = TableSheetModel(
            linkControllable: linkControllable,
            parent: nil,
            model: adventureModel,
            level: 0,
            module: .adventure,
            searchText: "",
            maxDepth: 20
        )
        
        // WHEN: Performing cross-module search
        await tableSheetModel.performSheetSearch(
            searchControllable: mockAdventureSearch,
            searchText: "Bathroom"
        )
        
        // THEN: Should create sub-sheet with Map module (not Adventure)
        let rowModel = ItemRowModel(itemId: mapItemId, typeId: .map)
        let subSheet = try #require(tableSheetModel.sheets[rowModel])
        
        #expect(subSheet.module == .map)  // ← Key assertion!
        #expect(subSheet.level == 1)
        #expect(subSheet.searchText == "Bathroom")
    }
    
    @Test("Nested cross-module search (Adventure → Map → Photo)")
    func nestedCrossModuleSearch() async throws {
        // GIVEN: Adventure links to Map, Map links to Photo
        let photoItemId = UUID()
        let photoEntryId = UUID()
        
        let photoItem = MockItem(
            id: photoItemId,
            name: "Bathroom Photo",
            entries: [
                MockEntry(
                    id: photoEntryId,
                    name: "Bathroom Sink",
                    content: "Close-up of ornate bathroom sink"
                )
            ]
        )
        
        let mapItemId = UUID()
        let bathroomMapEntryId = UUID()
        
        let mapItem = MockItem(
            id: mapItemId,
            name: "Tavern Floor Plan",
            entries: [
                MockEntry(
                    id: bathroomMapEntryId,
                    name: "Bathroom",
                    content: "See [Bathroom Photo](adr://photo/\(photoItemId.uuidString)/0) for details"
                )
            ]
        )
        
        let adventureItem = MockItem(
            id: UUID(),
            entries: [
                MockEntry(
                    id: UUID(),
                    name: "Tavern",
                    content: "[Tavern Map](adr://map/\(mapItemId.uuidString)/0)"
                )
            ]
        )
        
        // WHEN: Searching for "Bathroom Sink" from Adventure
        let result = await adventureSearchControllable.searchInSheet(
            itemId: adventureItem.id,
            searchText: "Bathroom Sink",
            includeLinks: true,
            rootManager: mockRootManager
        )
        
        // THEN: Should find the adventure entry (it links to map → photo chain)
        #expect(result.matchedEntries.count >= 1)
        
        // AND: Should have Map in cross-module matches
        let tavernMatch = result.matchedEntries.first
        let crossMatches = try #require(result.crossModuleMatches[tavernMatch!.entryId])
        
        let mapMatch = try #require(crossMatches.first { $0.linkedModule == .map })
        #expect(mapMatch.linkedItemId == mapItemId)
        
        // Note: The Photo link would be found when the Map sheet is expanded
        // and its own search is performed (recursive expansion)
    }
}

// MARK: - Mock Types

struct MockItem: ItemDataAccessable {
    let id: UUID
    var name: String = "Mock Item"
    var description: String = ""
    var entries: [MockEntry] = []
    var category: ItemListCategory = .all
    var specialCategory: Bool = false
    
    func filter(filter: String, includeEntries: Bool) -> Bool {
        name.localizedStandardContains(filter) || 
        description.localizedStandardContains(filter)
    }
}

struct MockEntry: EntryDataAccessable {
    let id: UUID
    var name: String = ""
    var content: String = ""
    
    func filter(with searchText: String) -> Bool {
        name.localizedStandardContains(searchText) ||
        content.localizedStandardContains(searchText)
    }
    
    func linkContent() -> String { content }
}

// Mock implementations would need to be fleshed out for actual testing
