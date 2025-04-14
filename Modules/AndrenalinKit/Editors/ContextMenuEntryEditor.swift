// @copyright André Trettin

import SwiftUI

public struct ContextMenuEntryEditor<EditController: EntryDataEditable, MenuContent: View>: View {
    public init(editControllable: EditController, entryId: UUID, @ViewBuilder menuView: @escaping () -> MenuContent) {
        self.editControllable = editControllable
        self.entryId = entryId
        self.menuView = menuView
    }
    
    let editControllable: EditController
    let entryId: UUID
    let menuView: () -> MenuContent
    
    public var body: some View {
        Button {
            editControllable.copy(entryIds: editControllable.editorModel.selection.isEmpty ? [entryId] : editControllable.editorModel.selection)
        } label: {
            if editControllable.editorModel.selection.count > 0 {
                Text("Copy \(editControllable.editorModel.selection.count) entry", bundle: .module)
            } else {
                Text("Copy row \(entryName(for: entryId))", bundle: .module)
            }
        }
#if !os(tvOS)
        .keyboardShortcut(KeyEquivalent("C"), modifiers: .command)
#endif
        Divider()
        Button {
            editControllable.move(entryId: entryId, up: true)
        } label: {
            Text("Move row up \(entryName(for: entryId))", bundle: .module)
        }
#if !os(tvOS)
        .keyboardShortcut(KeyEquivalent.leftArrow, modifiers: .command)
#endif
        
        Button {
            editControllable.move(entryId: entryId, up: false)
        } label: {
            Text("Move row down \(entryName(for: entryId))", bundle: .module)
        }
#if !os(tvOS)
        .keyboardShortcut(KeyEquivalent.rightArrow, modifiers: .command)
#endif
        
        menuView()
        
        Divider()
        Button(role: .destructive) {
            let entries = editControllable.editorModel.selection.isEmpty ? [entryId] : editControllable.editorModel.selection
            withAnimation { editControllable.editorModel.deleteAlertIds = entries }
        } label: {
            Label {
                Text(entryName(for: entryId, selection: editControllable.editorModel.selection), bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
            .foregroundStyle(.red)
        }
#if !os(tvOS)
        .keyboardShortcut(KeyEquivalent.delete, modifiers: [])
#endif
    }
    
    @MainActor 
    private func entryName(for entryId: UUID, selection: [UUID]) -> LocalizedStringKey {
        selection.count > 0 ? "Delete \(selection.count) entry" : "Delete row \(entryName(for: entryId))"
    }
    
    @MainActor 
    private func entryName(for entryId: UUID) -> String {
        String(entry(entryId).name.prefix(16))
    }
    
    @MainActor 
    private func entry(_ entryId: UUID) -> EditController.Model.Entry {
        editControllable.model[entryId]
    }
}
