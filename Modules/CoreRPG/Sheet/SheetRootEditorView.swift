// @copyright André Trettin

import SwiftUI

// Fix #2 + #3:
// - linkControllable and editorModel removed from init — they are no longer
//   needed here because the parent creates and owns SheetRootModel.
// - model and onChange(of: model.id) removed — the parent task handles
//   resetting the model when the selected item changes.
// - @State private var sheetRootModel replaced with a plain let — the parent
//   owns the instance via @State, so SheetRootEditorView just holds a reference.
//   Because SheetRootModel is @Observable, changes to its properties still drive
//   body re-evaluation without any extra wrappers needed here.
// - module removed — it was stored but never used in body.
//
// Root cause this solves:
// Previously SheetRootEditorView.init called State(wrappedValue: SheetRootModel(...))
// which evaluated SheetRootModel.init inside DetailEditorView.body's @Observable
// tracking window. This leaked tracking dependencies (locations, itemData) up to
// DetailEditorView, causing a tight re-render loop every time text rendered.

public struct SheetRootEditorView<LinkType: LinkDataTransferable>: View {
    public init(
        root: ItemRootController,
        sheetRootModel: SheetRootModel,
        headerTitle: String,
        linkTypes: LinkType.Type
    ) {
        self.root = root
        self.sheetRootModel = sheetRootModel
        self.headerTitle = headerTitle
        self.linkTypes = linkTypes
    }

    let root: ItemRootController
    let sheetRootModel: SheetRootModel
    let headerTitle: String
    let linkTypes: LinkType.Type

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        Section {
            SheetRootView(root: root, rootModel: sheetRootModel, isEditor: true, linkTypes: linkTypes)
        } header: {
            Text(headerTitle)
        }
    }
}
