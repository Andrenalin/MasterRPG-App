//// @copyright André Trettin
//
//import Testing
//import SwiftData
//@testable import CoreRPG
//import Foundation
//
//struct LinkRegisterControllerTests {
//
//    @MainActor func makeSut() throws -> (LinkRegisterController, ModelContainer) {
//        let modelContainer = try ModelContainer(for: LinkDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
//        return (LinkRegisterController(container: modelContainer), modelContainer)
//    }
//    
//    @MainActor @Test func testRegisterLinkNoDuplicates() throws {
//        // Given
//        let (sut, container) = try makeSut()
//        let sourceId = UUID()
//        let destinationId = UUID()
//        let sourceModule = NetworkModules.table
//        let destinationModule = NetworkModules.dice
//        
//        // When - Register the same link twice
//        let linkId1 = sut.register(sourceId: sourceId, sourceModule: sourceModule, destinationId: destinationId, destinationModule: destinationModule)
//        let linkId2 = sut.register(sourceId: sourceId, sourceModule: sourceModule, destinationId: destinationId, destinationModule: destinationModule)
//        
//        // Then - Verify only one link exists
//        let fetchDescriptor = FetchDescriptor<LinkDataModel>()
//        let allLinks = try container.mainContext.fetch(fetchDescriptor)
//        
//        #expect(allLinks.count == 1, "Expected only one link, but found \(allLinks.count)")
//        #expect(linkId1 == linkId2, "Expected same link ID when registering duplicate")
//        
//        let link = allLinks.first!
//        #expect(link.sourceId == sourceId)
//        #expect(link.sourceModule == sourceModule)
//        #expect(link.destinationId == destinationId)
//        #expect(link.destinationModule == destinationModule)
//        #expect(link.name == destinationModule.title)
//    }
//    
//    @MainActor @Test func testRegisterDifferentLinksCreatesSeparateEntries() throws {
//        // Given
//        let (sut, container) = try makeSut()
//        let sourceId1 = UUID()
//        let sourceId2 = UUID()
//        let destinationId = UUID()
//        let sourceModule = NetworkModules.table
//        let destinationModule = NetworkModules.dice
//        
//        // When - Register two different links
//        let linkId1 = sut.register(sourceId: sourceId1, sourceModule: sourceModule, destinationId: destinationId, destinationModule: destinationModule)
//        let linkId2 = sut.register(sourceId: sourceId2, sourceModule: sourceModule, destinationId: destinationId, destinationModule: destinationModule)
//        
//        // Then - Verify two links exist
//        let fetchDescriptor = FetchDescriptor<LinkDataModel>()
//        let allLinks = try container.mainContext.fetch(fetchDescriptor)
//        
//        #expect(allLinks.count == 2, "Expected two different links, but found \(allLinks.count)")
//        #expect(linkId1 != linkId2, "Expected different link IDs for different links")
//        
//        let sourceIds = Set(allLinks.map { $0.sourceId })
//        #expect(sourceIds.contains(sourceId1))
//        #expect(sourceIds.contains(sourceId2))
//    }
//    
//    @MainActor @Test func testRegisterLinkReplaceModelsWithDifferentLinkNumbers() throws {
//        // Given
//        let (sut, container) = try makeSut()
//        let sourceId = UUID()
//        let entryId = UUID()
//        let destinationId = UUID()
//        let destinationModule = NetworkModules.table
//        
//        // Create two LinkReplaceModels with same source but different linkNumbers
//        let link1 = LinkReplaceModel(
//            name: "Test Link",
//            module: .dice,
//            linkNumber: 0,
//            itemId: sourceId,
//            entryId: entryId,
//            markDown: "[Test Link](RPG://DICE/0/\(sourceId.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
//        let link2 = LinkReplaceModel(
//            name: "Test Link",
//            module: .dice,
//            linkNumber: 1,
//            itemId: sourceId,
//            entryId: entryId,
//            markDown: "[Test Link](RPG://DICE/1/\(sourceId.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
//        // When - Register both links in same batch
////        let registeredIds = sut.register(links: [link1, link2], destinationId: destinationId, destinationModule: destinationModule)
////        
////        // Then - Only one link should be registered (deduplication within batch)
////        let fetchDescriptor = FetchDescriptor<LinkDataModel>()
////        let allLinks = try container.mainContext.fetch(fetchDescriptor)
////        
////        #expect(allLinks.count == 1, "Expected only one link due to deduplication, but found \(allLinks.count)")
////        #expect(registeredIds.count == 1, "Expected only one registered ID, but got \(registeredIds.count)")
////        
////        let link = allLinks.first!
////        #expect(link.sourceId == sourceId)
////        #expect(link.sourceEntryId == entryId)
////        #expect(link.sourceModule == .dice)
////        #expect(link.destinationId == destinationId)
////        #expect(link.destinationModule == destinationModule)
//    }
//    
//    @MainActor @Test func testRegisterLinkReplaceModelsWithDifferentSources() throws {
//        // Given
//        let (sut, container) = try makeSut()
//        let sourceId1 = UUID()
//        let sourceId2 = UUID()
//        let entryId = UUID()
//        let destinationId = UUID()
//        let destinationModule = NetworkModules.table
//        
//        // Create two LinkReplaceModels with different sources
//        let link1 = LinkReplaceModel(
//            name: "Test Link 1",
//            module: .dice,
//            linkNumber: 0,
//            itemId: sourceId1,
//            entryId: entryId,
//            markDown: "[Test Link 1](RPG://DICE/0/\(sourceId1.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
//        let link2 = LinkReplaceModel(
//            name: "Test Link 2",
//            module: .dice,
//            linkNumber: 0,
//            itemId: sourceId2,
//            entryId: entryId,
//            markDown: "[Test Link 2](RPG://DICE/0/\(sourceId2.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
////        // When - Register both links in same batch
////        let registeredIds = sut.register(links: [link1, link2], destinationId: destinationId, destinationModule: destinationModule)
////        
////        // Then - Both links should be registered (different sources)
////        let fetchDescriptor = FetchDescriptor<LinkDataModel>()
////        let allLinks = try container.mainContext.fetch(fetchDescriptor)
////        
////        #expect(allLinks.count == 2, "Expected two links with different sources, but found \(allLinks.count)")
////        #expect(registeredIds.count == 2, "Expected two registered IDs, but got \(registeredIds.count)")
////        
////        let sourceIds = Set(allLinks.map { $0.sourceId })
////        #expect(sourceIds.contains(sourceId1))
////        #expect(sourceIds.contains(sourceId2))
//    }
//    
//    @MainActor @Test func testRegisterLinkReplaceModelsWithMixedDuplicatesAndUnique() throws {
//        // Given
//        let (sut, container) = try makeSut()
//        let sourceId1 = UUID()
//        let sourceId2 = UUID()
//        let entryId = UUID()
//        let destinationId = UUID()
//        let destinationModule = NetworkModules.table
//        
//        // Create multiple LinkReplaceModels: 2 duplicates of source1, 1 unique source2
//        let link1a = LinkReplaceModel(
//            name: "Test Link 1",
//            module: .dice,
//            linkNumber: 0,
//            itemId: sourceId1,
//            entryId: entryId,
//            markDown: "[Test Link 1](RPG://DICE/0/\(sourceId1.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
//        let link1b = LinkReplaceModel(
//            name: "Test Link 1",
//            module: .dice,
//            linkNumber: 1,  // Different link number, same source
//            itemId: sourceId1,
//            entryId: entryId,
//            markDown: "[Test Link 1](RPG://DICE/1/\(sourceId1.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
//        let link2 = LinkReplaceModel(
//            name: "Test Link 2",
//            module: .dice,
//            linkNumber: 0,
//            itemId: sourceId2,
//            entryId: entryId,
//            markDown: "[Test Link 2](RPG://DICE/0/\(sourceId2.uuidString))",
//            command: nil,
//            range: "".startIndex..<"".endIndex
//        )
//        
////        // When - Register all links in same batch
////        let registeredIds = sut.register(links: [link1a, link1b, link2], destinationId: destinationId, destinationModule: destinationModule)
////        
////        // Then - Only 2 links should be registered (link1a/link1b deduplicated, link2 unique)
////        let fetchDescriptor = FetchDescriptor<LinkDataModel>()
////        let allLinks = try container.mainContext.fetch(fetchDescriptor)
////        
////        #expect(allLinks.count == 2, "Expected two unique links, but found \(allLinks.count)")
////        #expect(registeredIds.count == 2, "Expected two registered IDs, but got \(registeredIds.count)")
////        
////        let sourceIds = Set(allLinks.map { $0.sourceId })
////        #expect(sourceIds.contains(sourceId1))
////        #expect(sourceIds.contains(sourceId2))
//    }
//}
