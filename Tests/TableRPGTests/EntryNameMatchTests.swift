// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import Testing

@testable import TableRPG

/// CODE_AUDIT_Folder §9.10: edited entries are matched to existing ones by name, each once.
@MainActor
struct EntryNameMatchTests {
    @Test("Two entries with the same name keep their own ids")
    func sameNamedEntriesKeepTheirIds() throws {
        let root = TableRootModel.testRoot(diceRoot: DiceRootModel.testRoot(), pdfRoot: PdfRootModel.testRoot())
        let model = TableModel.empty.copy()
        model.entries = [
            root.editController.create(name: "Row", content: "one"),
            root.editController.create(name: "Row", content: "two")
        ]
        root.itemController.resetModel(with: model)
        let originalIds = model.entries.map(\.id)

        let edited = [
            root.editController.create(name: "Row", content: "first"),
            root.editController.create(name: "Row", content: "second")
        ]
        let merged = root.editController.merge(itemId: model.id, entries: edited)

        #expect(merged.map(\.id) == originalIds)
        #expect(merged.map(\.content) == ["first", "second"])
    }
}
