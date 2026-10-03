// @copyright André Trettin

import Foundation

/// Generic replacement for the near-identical per-module `EditController` structs — a
/// module with no extra state beyond `itemController`/`tagController`/`editorModel`
/// needs only a one-line adoption:
/// ```swift
/// typealias EditController = GenericEditController<DiceModel>
/// ```
/// Module-specific extra *behavior* (no extra stored state, just extra methods — e.g.
/// PdfRPG's bookmark helpers) can still live in a same-file
/// `extension GenericEditController<PdfModel> { ... }`, mirroring
/// `GenericItemController`. A module keeps its own `EditController` when it needs an extra
/// *stored* property (a stored property can't be added via extension), or a protocol
/// conformance another module already adds to a specialisation: `GenericEditController<PdfModel>`
/// conforms to `EntryDataEditable`, and a generic type can't conform to one protocol twice, so
/// RuleRPG's `EntryDataEditable` controller stays its own type.
/// See CODE_AUDIT_EditItem §9.1, CODE_AUDIT_Folder §9.3.
public struct GenericEditController<
    Model: ItemDataAccessible & ItemDiffComparable & ItemLinkRegistrable & ModelType
>: Sendable {
    @MainActor public init(itemController: any ItemControllable, tagController: TagController) {
        self.itemController = itemController
        self.tagController = tagController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        self.editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
    }

    public let itemController: any ItemControllable
    public let tagController: TagController
    public let editorModel: ItemEditorModel
}

extension GenericEditController: EditControllable {
    public var itemControllable: any ItemControllable { itemController }
}
