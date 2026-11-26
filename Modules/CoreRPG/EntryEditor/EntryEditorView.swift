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
            // The Ask AI button steps aside: it takes room from the editor and invites a tap
            // in the middle of an edit.
            .preference(key: EditorOverlayPresentedPreferenceKey.self, value: true)
            .transition(editorTransition)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: editorModel.entryId)
        }
    }

    // AppKit doesn't reliably redraw the NSTextView backing a TextEditor when it's caught in
    // a SwiftUI scale-transform transition on macOS: the text can stay blank or mis-sized until
    // something else (e.g. a window resize) forces a relayout. A plain fade avoids the transform.
    private var editorTransition: AnyTransition {
#if os(macOS)
        .opacity
#else
        .scale
#endif
    }
}

#Preview {
    EntryEditorView(
        rootManager: RootManager.preview(fake: ItemRootController.fake),
        editorModel: SheetEditorModel(itemId: UUID(), entryId: UUID(), module: .none),
        linkTypes: EmptyLinkTransferable.self
    )
}
