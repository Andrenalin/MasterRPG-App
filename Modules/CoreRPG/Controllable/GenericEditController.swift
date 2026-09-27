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
/// `GenericItemController`. A module that needs an extra *stored* property
/// (GeneratorRPG's `selectionReference`) can't use this — a stored property can't be
/// added later via extension — and keeps its own bespoke `EditController` instead.
/// See CODE_AUDIT_EditItem §9.1.
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
