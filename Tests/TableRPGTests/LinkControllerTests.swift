// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import TableRPG

@MainActor
struct LinkControllerTests {
    @Test func toggleTextLink() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await root.linkController
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: UUID(), entryId: nil, command: nil, in: "", shareResult: nil, toggler: nil, editAction: nil)
        #expect(result.isEmpty)
        
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: nil, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️ W20 -- 20 Entries⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: result, shareResult: nil, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️ W20 -- 20 Entries⬅️"
        #expect(result == text)
    }

    @Test func toggleWithShare() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
        
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: nil, editAction: nil)
        var expectedText = "\(text)➡️[Share](RPG://TABLES/500/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/share) W20 -- 20 Entries⬅️"
        #expect(result == expectedText)
                
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: nil, editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://TABLES/500/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/share) W20 -- 20 Entries⬅️"
        #expect(result.starts(with: expectedText))
    }
    
    @Test func toggleWithShareAndToggler() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
                
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: toggler(), editAction: nil)
        var expectedText = "\(text)➡️[Share](RPG://TABLES/500/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/share) W20 -- 20 Entries⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: nil)
        expectedText = "\(text)➡️[Share](RPG://TABLES/500/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/share) W20 -- 20 Entries⬅️"
        #expect(result == expectedText)
    }

    @Test func toggleWithShareTogglerAndEditAction() async throws {
        let root = try await MockRoot.importTestData()
        
        let sut = await root.linkController
        let shareResult: ShareValueResult = await ShareValueResult.preview()
                
        let firstItem = await root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0])
        let text = await sut.generateLink(itemId: firstItem.id)
        var result = await sut.toggleTextLink(linkNumber: 0, itemId: firstItem.id, entryId: nil, command: nil, in: text, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        var expectedText = "\(text)➡️[Share](RPG://TABLES/500/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/share) W20 -- 20 Entries [Remove](RPG://TABLES/300/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/remove)⬅️"
        #expect(result == expectedText)
        
        result = await sut.toggleTextLink(linkNumber: LinkType.share.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.share.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        expectedText = "\(text)➡️[Share](RPG://TABLES/500/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/share) W20 -- 20 Entries [Remove](RPG://TABLES/300/6E013A18-1A45-415C-95B1-A7BB07ABDDBE/remove)⬅️"
        #expect(result == expectedText)

        result = await sut.toggleTextLink(linkNumber: LinkType.remove.linkNumberAddition, itemId: firstItem.id, entryId: nil, command: LinkType.remove.rawValue, in: result, shareResult: shareResult, toggler: toggler(), editAction: editAction())
        #expect(result == "Abenteuerhooks")
    }
    
    @Test func toogleBrokenLink() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let text = "**1-3**: [Axt](RPG://TABLES/0/307BF818-787A-41E2-91A7-7397AE9BB36F/E940E958-3152-41A3-9EF5-A456A5EE17C8)"
        let result = await sut.handleTextLink(url: URL(string: "RPG://TABLES/0/307BF818-787A-41E2-91A7-7397AE9BB36F/E940E958-3152-41A3-9EF5-A456A5EE17C8")!, in: text, shareResult: nil, toggler: nil, editAction: nil)
        #expect(result == "**1-3**: [Axt](RPG://TABLES/0/307BF818-787A-41E2-91A7-7397AE9BB36F/E940E958-3152-41A3-9EF5-A456A5EE17C8➡️🚨 Table Link is broken⬅️)")
    }

    @Test func handleLink() async throws {
        let root = try await MockRoot.importTestData()
        let sut = await root.linkController
        let text = "**4**: [Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1)"
        let result = await sut.handleTextLink(url: URL(string: "RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1")!, in: text, shareResult: nil, toggler: nil, editAction: nil)
        #expect(result == "**4**: [Dolch](RPG://TABLES/0/84087225-BF5D-4398-B5F3-FDE0A0B79250/EDB0E646-8F15-4D2B-A63C-B31C11E0F1E1➡️🚨 Table Link is broken⬅️)")
    }

    @MainActor
    private func shareResult() -> ShareValueResult {
        ShareValueResult.preview()
    }
    
    private func toggler() -> ((UUID, NetworkModules) async -> Void) {
        { _, _ in }
    }
    
    private func editAction() -> ((ItemRowModel) -> Bool) {
        { _ in true }
    }
}
