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
    @State private var isDropTargeted: Bool = false

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
        EntryEditorContent(entry: entry, editModel: editModel) {
            headerView
        }
    }

    var activeEditController: any EntryDataEditable {
        rootManager.itemRootController(for: editorModel.module)?.editControllable as! (any EntryDataEditable)
    }

    var backGroundColor: Color {
        activeEditController.itemControllable.config.module.color
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

    func save() {
        editModel.resetText()
        withAnimation {
            if let itemId = editorModel.itemId {
                activeEditController.update(itemId: itemId, entryId: entry.id, name: editModel.name, content: editModel.text)
            }
            editorModel.entryId = nil
        }
    }

    var dropBackgroundColor: Color {
#if os(iOS) || os(visionOS)
        isDropTargeted ? Color.accentColor : Color(.systemGray6)
#elseif os(tvOS)
        isDropTargeted ? Color.accentColor : .clear
#else
        isDropTargeted ? Color.accentColor : Color(.controlBackgroundColor)
#endif
    }

    @ViewBuilder var dropLinkButton: some View {
#if !os(tvOS)
        Text("Drop Links", bundle: .module)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(dropBackgroundColor)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
            )
            .dropDestination(for: linkTypes) { items, dropSession in
                isDropTargeted = dropSession.phase == .entering
                editModel.resetText()
                if let itemId = editorModel.itemId {
                    activeEditController.update(itemId: itemId, entryId: entry.id, name: editModel.name, content: editModel.text)
                    items.forEach {
                        activeEditController.add(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, destinationItemId: itemId, destinationEntryId: entry.id)
                    }
                }
            }
#endif
    }
    
    var headerView: some View {
        HStack {
            Button {
                withAnimation { editorModel.entryId = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
            }
            .padding()
#if !os(visionOS)
            .glassEffectAll(.regular.interactive())
#endif
            Spacer()
            
            dropLinkButton
            
            Spacer()
            
            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(.headline)
            }
            .padding()
#if !os(visionOS)
            .glassEffectAll(.regular.interactive())
#endif
        }
        .buttonStyle(.borderless)
    }
}
