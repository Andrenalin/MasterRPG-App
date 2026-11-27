// @copyright André Trettin

@testable import CoreRPG
import Foundation
import Testing

@Suite("Entry text editing")
struct ResetEntryTests {
    @Test("Attributed entry name preserves Character-style links")
    @MainActor
    func attributedNamePreservesLinks() {
        let itemId = UUID.fixture1
        let entryId = UUID.fixture2
        let destinationItemID = UUID.fixture3
        let destinationEntryID = UUID.fixture4
        let markdown = "[Strength](RPG://TABLES/0/\(destinationItemID.uuidString)/\(destinationEntryID.uuidString))"
        let entry = FakeEntryModel(
            id: entryId,
            name: "Attack: \(markdown)",
            content: "Uses the linked value"
        )
        let model = TextEditModel(linkRegisterController: LinkRegisterController(root: nil))

        model.reset(
            entry: entry,
            source: ItemRowModel(itemId: itemId, entryId: entryId, typeId: .value)
        )

        #expect(String(model.attributedName.characters) == "Attack: Strength")
        #expect(model.nameLinks.count == 1)
        #expect(model.attributedName.runs.contains { $0.linkContent != nil })

        model.resetNameText()

        #expect(model.name == "Attack: \(model.nameLinks[0].urlMarkDown)")
    }

    @Test("Editing attributed name keeps link metadata and new text")
    @MainActor
    func editingAttributedNameKeepsLinks() {
        let entryId = UUID.fixture2
        let destinationItemID = UUID.fixture3
        let markdown = "[Dexterity](RPG://TABLES/0/\(destinationItemID.uuidString))"
        let entry = FakeEntryModel(id: entryId, name: markdown, content: "")
        let model = TextEditModel(linkRegisterController: LinkRegisterController(root: nil))

        model.reset(
            entry: entry,
            source: ItemRowModel(itemId: .fixture1, entryId: entryId, typeId: .value)
        )
        model.attributedName.append(AttributedString(" bonus"))
        model.resetNameText()

        #expect(model.name == "\(model.nameLinks[0].urlMarkDown) bonus")
    }

    @Test("Plain attributed entry name stays plain")
    @MainActor
    func plainAttributedName() {
        let entry = FakeEntryModel(id: .fixture2, name: "Armor", content: "")
        let model = TextEditModel(linkRegisterController: LinkRegisterController(root: nil))

        model.reset(
            entry: entry,
            source: ItemRowModel(itemId: .fixture1, entryId: entry.id, typeId: .value)
        )
        model.resetNameText()

        #expect(model.name == "Armor")
        #expect(model.nameLinks.isEmpty)
    }
}
