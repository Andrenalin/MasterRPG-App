////
////  ResetEntryTests.swift
////  MasterRPG
////
////  Created by Andre Trettin on 27/11/2568 BE.
////
//
//@testable import CoreRPG
//import Testing
//import SwiftData
//import Foundation
//
//@Suite("Reset Entry Tests")
//struct ResetEntryTests {
//    
//    @Test("Reset entry preserves text with links when text unchanged")
//    @MainActor
//    func resetEntryPreservesLinksWhenTextUnchanged() async throws {
//        // Given
//        let modelContainer = try ModelContainer(for: LinkDataModel.self, configurations: .init(isStoredInMemoryOnly: true))
//        let linkController = LinkRootController(container: modelContainer, root: RootManager.preview(fake: FakeItemRootController.fake))
//        
//        // Create a link and register it
//        let link = linkController.register(
//            name: "Apple",
//            sourceId: Foundation.UUID(),
//            sourceModule: NetworkModules.adventure,
//            destinationId: Foundation.UUID(),
//            destinationModule: NetworkModules.table
//        )
//        
//        let originalText = "Check out [Apple](RPG://\(link.id.uuidString)) for more info"
//        let entry = FakeEntryModel(id: Foundation.UUID(), name: "Test Entry", content: originalText)
//        let source = ItemRowModel(itemId: Foundation.UUID(), entryId: entry.id, typeId: NetworkModules.adventure)
//        
//        let textEditModel = TextEditModel(linkRegisterController: linkController)
//        
//        // When - reset with entry (this sets the text from entry.content)
//        textEditModel.reset(entry: entry, source: source)
//        
//        // Store the text before resetText
//        let textBeforeReset = textEditModel.text
//        
//        // Call resetText which rebuilds plain text from attributedText
//        textEditModel.resetText()
//        
//        // Then
//        #expect(textEditModel.text == originalText, "Text should remain unchanged")
//        #expect(!textEditModel.links.isEmpty, "Links should still be present")
//        #expect(textEditModel.links.count == 1, "Should have exactly one link")
//        #expect(textEditModel.links.first?.id == link.id, "Link ID should match")
//        
//        // Verify the attributed text contains link information
//        let hasLinkAttribute = textEditModel.attributedText.runs.contains { run in
//            run[AttributeScopes.AndrenalinKitAttributes.LinkContentAttribute.self] != nil
//        }
//        #expect(hasLinkAttribute, "Attributed text should contain link attributes")
//    }
//    
//    @Test("Reset entry preserves attributed text when attributedText unchanged")
//    @MainActor
//    func resetEntryPreservesAttributedTextWhenUnchanged() async throws {
//        // Given
//        let modelContainer = try ModelContainer(for: LinkDataModel.self, configurations: .init(isStoredInMemoryOnly: true))
//        let linkController = LinkRegisterController(container: modelContainer)
//        
//        // Create multiple links
//        let link1 = linkController.register(
//            name: "FirstLink",
//            sourceId: Foundation.UUID(),
//            sourceModule: NetworkModules.audio,
//            destinationId: Foundation.UUID(),
//            destinationModule: NetworkModules.adventure
//        )
//        
//        let link2 = linkController.register(
//            name: "SecondLink",
//            sourceId: Foundation.UUID(),
//            sourceModule: NetworkModules.audio,
//            destinationId: Foundation.UUID(),
//            destinationModule: NetworkModules.table
//        )
//        
//        let originalText = "Visit [FirstLink](RPG://\(link1.id.uuidString)) and [SecondLink](RPG://\(link2.id.uuidString))"
//        let entry = FakeEntryModel(id: Foundation.UUID(), name: "Multi Link Entry", content: originalText)
//        let source = ItemRowModel(itemId: Foundation.UUID(), entryId: entry.id, typeId: NetworkModules.audio)
//        
//        let textEditModel = TextEditModel(linkRegisterController: linkController)
//        
//        // When - reset with entry
//        textEditModel.reset(entry: entry, source: source)
//        
//        // Store original state
//        let originalLinkCount = textEditModel.links.count
//        
//        // Don't modify text or attributedText, just call resetText
//        textEditModel.resetText()
//        
//        // Then
//        #expect(textEditModel.text == originalText, "Text should be preserved")
//        #expect(textEditModel.links.count == originalLinkCount, "Link count should remain the same")
//        #expect(textEditModel.links.count == 2, "Should have exactly two links")
//        
//        // Verify both links are present
//        let linkIds = Set(textEditModel.links.map(\.id))
//        #expect(linkIds.contains(link1.id), "First link should be present")
//        #expect(linkIds.contains(link2.id), "Second link should be present")
//        
//        // Verify the markdown format is preserved after resetText
//        #expect(textEditModel.text.contains("[FirstLink](RPG://\(link1.id.uuidString))"), "First link markdown should be preserved")
//        #expect(textEditModel.text.contains("[SecondLink](RPG://\(link2.id.uuidString))"), "Second link markdown should be preserved")
//    }
//    
//    @Test("Reset entry with empty text clears links")
//    @MainActor
//    func resetEntryWithEmptyTextClearsLinks() async throws {
//        // Given
//        let modelContainer = try ModelContainer(for: LinkDataModel.self, configurations: .init(isStoredInMemoryOnly: true))
//        let linkController = LinkRegisterController(container: modelContainer)
//        
//        let link = linkController.register(
//            name: "TestLink",
//            sourceId: Foundation.UUID(),
//            sourceModule: NetworkModules.adventure,
//            destinationId: Foundation.UUID(),
//            destinationModule: NetworkModules.table
//        )
//        
//        let originalText = "Text with [TestLink](RPG://\(link.id.uuidString))"
//        let textEditModel = TextEditModel(linkRegisterController: linkController)
//        
//        // Set up initial state with a link
//        let initialEntry = FakeEntryModel(id: Foundation.UUID(), name: "Initial", content: originalText)
//        let initialSource = ItemRowModel(itemId: Foundation.UUID(), entryId: initialEntry.id, typeId: NetworkModules.adventure)
//        textEditModel.reset(entry: initialEntry, source: initialSource)
//        
//        #expect(textEditModel.links.count == 1, "Should start with one link")
//        
//        // When - reset with empty entry
//        let emptyEntry = FakeEntryModel(id: Foundation.UUID(), name: "Empty", content: "")
//        let source = ItemRowModel(itemId: Foundation.UUID(), entryId: emptyEntry.id, typeId: NetworkModules.adventure)
//        textEditModel.reset(entry: emptyEntry, source: source)
//        textEditModel.resetText()
//        
//        // Then
//        #expect(textEditModel.text == "", "Text should be empty")
//        #expect(textEditModel.links.isEmpty, "Links should be cleared")
//    }
//}
