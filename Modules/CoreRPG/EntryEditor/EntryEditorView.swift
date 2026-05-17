// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditorView<LinkType: LinkDataTransferable>: View {
    public init(rootManager: RootManager, editorModel: SheetEditorModel, linkTypes: LinkType.Type) {
        self.rootManager = rootManager
        self.editorModel = editorModel
        self.linkTypes = linkTypes
        let editController = rootManager.itemRootController(for: editorModel.module)?.editControllable as? (any EntryDataEditable)
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: editController?.linkRegisterController))
    }
    
    let rootManager: RootManager
    let editorModel: SheetEditorModel
    let linkTypes: LinkType.Type
    
    @State private var editModel: TextEditModel
    
    public var body: some View {
        if isActive, let itemId = editorModel.itemId, let entryId = editorModel.entryId {
            // Cache entry once per view update
            let currentEntry = entry
            content(entry: currentEntry)
                .id(itemId)
            // Combine onChange handlers to avoid duplicate reset calls
                .onChange(of: currentEntry.content, initial: true) { _, _ in
                    updateEditModel(entry: currentEntry, itemId: itemId, entryId: entryId)
                }
                .onChange(of: currentEntry.name) { _, _ in
                    updateEditModel(entry: currentEntry, itemId: itemId, entryId: entryId)
                }
                .transition(.scale)
                .animation(.bouncy, value: isActive)
        }
    }
    
    private func updateEditModel(entry: any EntryDataAccessable, itemId: UUID, entryId: UUID) {
        editModel.reset(entry: entry, source: ItemRowModel(itemId: itemId, entryId: entryId, typeId: editorModel.module))
    }
    
    func content(entry: any EntryDataAccessable) -> some View {
        EntryEditorContent(
            editController: activeEditController,
            editorModel: editorModel,
            itemId: editorModel.itemId ?? UUID(),
            editModel: editModel,
            entry: entry,
            linkTypes: linkTypes
        )
    }
    
    var activeEditController: any EntryDataEditable {
        rootManager.itemRootController(for: editorModel.module)?.editControllable as! (any EntryDataEditable)
    }
    
    var isActive: Bool {
#if os(iOS)
        guard !(rootManager.itemRootController(for: editorModel.module)?.editControllable.editorModel.deactivateEntryEditor ?? false) else { return false }
#endif
        return editorModel.entryId != nil
    }
    
    var entry: any EntryDataAccessable {
        activeEditController.itemControllable.itemOrEmpty(for: editorModel.itemId ?? UUID())[editorModel.entryId ?? UUID()]
    }
}
