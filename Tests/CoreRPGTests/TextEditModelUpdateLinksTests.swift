// @copyright André Trettin

@testable import CoreRPG
import Foundation
import SwiftUI
import Testing

/// The description editor flickered when its selection changed: the editor writes the text back
/// with the colors it applied, and the model then rebuilt the whole attributed text.
@Suite("Text edit model update links")
struct TextEditModelUpdateLinksTests {
    @MainActor
    private func model(content: String) -> TextEditModel {
        let model = TextEditModel(linkRegisterController: LinkRegisterController(root: nil))
        model.reset(
            entry: FakeEntryModel(id: .fixture2, name: "Monster", content: content),
            source: ItemRowModel(itemId: .fixture1, entryId: .fixture2, typeId: .value)
        )
        return model
    }

    private var content: String {
        "Bites [Strength](RPG://TABLES/0/\(UUID.fixture3.uuidString)) twice"
    }

    @Test("An attribute-only write by the editor does not rebuild the text")
    @MainActor
    func attributeOnlyChangeKeepsText() {
        let model = model(content: content)
        model.attributedText.foregroundColor = .red

        model.settleLinks()

        #expect(model.attributedText.runs.allSatisfy { $0.foregroundColor == .red }, "the editor's text was kept, not replaced")
        #expect(model.text == content)
    }

    @Test("A change in the words is parsed again")
    @MainActor
    func textChangeRebuilds() {
        let model = model(content: content)
        model.attributedText.foregroundColor = .red
        model.attributedText.append(AttributedString(" and more"))

        model.settleLinks()

        #expect(model.text.hasSuffix(" and more"))
        #expect(model.links.count == 1)
        #expect(model.attributedText.runs.allSatisfy { $0.foregroundColor == nil }, "the text was rebuilt from the words")
    }
}
