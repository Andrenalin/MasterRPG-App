// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.15: the in-memory sheet editing session that Table (and any module)
/// uses to shape freeform content: a wrapping root with one entry linked to the result item.
@MainActor
@Suite("Simple sheet editing session")
struct SimpleSheetEditingSessionTests {
    @Test("The wrapping root has one entry, named as asked, that links to the empty result item")
    func startsWithOneWrappingEntry() throws {
        let session = SimpleSheetEditingSession(module: .table, name: "Loot")

        #expect(session.itemId != session.resultItemId)
        let root = try #require(session.currentModel)
        #expect(root.entries.count == 1)
        let wrapper = try #require(root.entries.first)
        #expect(wrapper.name == "Loot")
        #expect(wrapper.childId == session.resultItemId)
        let result = try #require(session.resultModel)
        #expect(result.entries.isEmpty)
    }

    @Test("Without a name the wrapping entry has none")
    func defaultNameIsEmpty() {
        let session = SimpleSheetEditingSession(module: .table)

        #expect(session.currentModel?.entries.first?.name == "")
    }

    @Test("Inserted entries land in the result item, in order, and never in the wrapping root")
    func insertedEntriesGoToTheResult() throws {
        let session = SimpleSheetEditingSession(module: .table, name: "Loot")

        let first = session.editController.insertEntry(itemId: session.resultItemId, name: "Sword", content: "1d8", position: .end)
        let second = session.editController.insertEntry(itemId: session.resultItemId, name: "Shield", content: "AC 2", position: .end)

        let result = try #require(session.resultModel)
        #expect(result.entries.map(\.name) == ["Sword", "Shield"])
        #expect(result.entries.map(\.content) == ["1d8", "AC 2"])
        #expect(result.entries.map(\.id) == [first, second].compactMap { $0 })
        #expect(session.currentModel?.entries.count == 1, "the wrapping root keeps its one entry")
    }

    @Test("An entry can be inserted after another one")
    func insertAfter() throws {
        let session = SimpleSheetEditingSession(module: .table)
        let a = try #require(session.editController.insertEntry(itemId: session.resultItemId, name: "A", content: "", position: .end))
        _ = session.editController.insertEntry(itemId: session.resultItemId, name: "C", content: "", position: .end)

        _ = session.editController.insertEntry(itemId: session.resultItemId, name: "B", content: "", position: .after(a))

        #expect(session.resultModel?.entries.map(\.name) == ["A", "B", "C"])
    }

    @Test("Two sessions are independent")
    func sessionsAreIndependent() {
        let first = SimpleSheetEditingSession(module: .table, name: "One")
        let second = SimpleSheetEditingSession(module: .table, name: "Two")

        _ = first.editController.insertEntry(itemId: first.resultItemId, name: "Only in one", content: "", position: .end)

        #expect(first.resultModel?.entries.count == 1)
        #expect(second.resultModel?.entries.isEmpty == true)
        #expect(first.itemId != second.itemId)
        #expect(first.resultItemId != second.resultItemId)
    }

    @Test("The session has its own root manager, so nothing reaches the app's modules")
    func sessionHasItsOwnRootManager() {
        let session = SimpleSheetEditingSession(module: .table, name: "Loot")

        #expect(session.rootController.rootManager != nil)
        #expect(session.rootController.itemControllable.itemOrEmpty(for: session.itemId).id == session.itemId)
    }
}
