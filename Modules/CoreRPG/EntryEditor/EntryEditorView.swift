// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditorView<LinkType: LinkDataTransferable>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    public init(rootManager: RootManager, editorModel: SheetEditorModel, linkTypes: LinkType.Type) {
        self.rootManager = rootManager
        self.editorModel = editorModel
        self.linkTypes = linkTypes
    }
    
    let rootManager: RootManager
    let editorModel: SheetEditorModel
    let linkTypes: LinkType.Type
    
    public var body: some View {
        // Optimization: Cache controller lookups to avoid repeated optional chaining
        let rootController = rootManager.itemRootController(for: editorModel.module)
        let editController = rootController?.editControllable as? (any EntryDataEditable)
        
        if let itemId = editorModel.itemId, 
           let entryId = editorModel.entryId, 
           let editController,
           !editController.editorModel.deactivateEntryEditor {
            
            EntryEditorContent(
                editController: editController,
                editorModel: editorModel,
                itemId: itemId,
                entry: editController.itemControllable.itemOrEmpty(for: itemId)[entryId],
                linkTypes: linkTypes
            )
            .id(itemId)
            .transition(.scale)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: editorModel.entryId)
        }
    }
}

#Preview {
    EntryEditorView(
        rootManager: RootManager.preview(fake: ItemRootController.fake),
        editorModel: SheetEditorModel(itemId: UUID(), entryId: UUID(), module: .none),
        linkTypes: EmptyLinkTransferable.self
    )
}
