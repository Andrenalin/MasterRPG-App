// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditorView<LinkType: LinkDataTransferable>: View {
    public init(rootManager: RootManager, editorModel: SheetEditorModel, linkTypes: LinkType.Type) {
        self.rootManager = rootManager
        self.editorModel = editorModel
        self.linkTypes = linkTypes
    }
    
    let rootManager: RootManager
    let editorModel: SheetEditorModel
    let linkTypes: LinkType.Type
    
    public var body: some View {
        if let itemId = editorModel.itemId, let entryId = editorModel.entryId, let editController, !editController.editorModel.deactivateEntryEditor {

            EntryEditorContent(
                editController: editController,
                editorModel: editorModel,
                itemId: itemId,
                entry: editController.itemControllable.itemOrEmpty(for: itemId)[entryId],
                linkTypes: linkTypes
            )
            .id(itemId)
            .transition(.scale)
            .animation(.bouncy, value: editorModel.entryId)
        }
    }
    
    var rootController: (any ItemRootControllable)? {
        rootManager.itemRootController(for: editorModel.module)
    }
    
    var editController: (any EntryDataEditable)? {
        rootController?.editControllable as? (any EntryDataEditable)
    }
}
