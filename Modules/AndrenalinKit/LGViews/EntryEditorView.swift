// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditorView: View {
    public init(editController: any EntryDataEditable) {
        self.editController = editController
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: editController.linkRegisterControllable))
    }
    
    let editController: any EntryDataEditable
    @FocusState private var currentFocus: EntryEditorFocusField?
    @State private var editModel: TextEditModel
    
    public var body: some View {
        Group {
            if isActive {
                content(entry: entry)
                    .onAppear {
                        editModel.reset(entry: entry, source: ItemRowModel(itemId: editController.model.id, entryId: entry.id, typeId: editController.itemControllable.itemDataModel.networkModule))
                    }
            }
        }
        .transition(.scale)
        .animation(.bouncy, value: isActive)
    }
    
    func content(entry: any EntryDataAccessable) -> some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button {
                            withAnimation { editController.editorModel.currentEntryId = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                        }
                        .padding()
#if !os(visionOS)
                        .glassEffect(.regular.interactive())
#endif
                        Spacer()
                        
                        Button {
                            save()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.headline)
                        }
                        .padding()
#if !os(visionOS)
                        .glassEffect(.regular.interactive())
#endif
                    }
                    .buttonStyle(.borderless)

                    EntryNameEditor(editModel: editModel, currentFocus: $currentFocus)
                    
                    EntryContentEditor(editModel: editModel, currentFocus: $currentFocus)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.95).gradient)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var backGroundColor: Color {
        editController.itemControllable.itemDataModel.networkModule.color
    }
    
    var isActive: Bool {
        entry.id == editController.editorModel.currentEntryId
    }
        
    var entry: any EntryDataAccessable {
        editController.model[editController.editorModel.currentEntryId ?? UUID()]
    }
    
    func save() {
        editModel.resetText()
        withAnimation {
            editController.update(entryId: entry.id, name: editModel.name, content: editModel.text)
            editController.editorModel.currentEntryId = nil
        }
    }
}

enum EntryEditorFocusField {
    case name
    case information
}


struct EntryNameEditor: View {
    let editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?
    
    var body: some View {
        @Bindable var editModel = editModel
        
        Text("Name", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack {
            TextField(text: $editModel.name, prompt: Text("Enter a name", bundle: .module)) {
                Text("Name", bundle: .module)
            }
            .focused($currentFocus, equals: .name)
            .labelsHidden()
            .textFieldStyle(.plain)
            
            Button {
                withAnimation { editModel.name = "" }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .opacity(editModel.name.isEmpty ? 0: 1)
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
    }
}

struct EntryContentEditor: View {
    let editModel: TextEditModel
    @FocusState.Binding var currentFocus: EntryEditorFocusField?

    var body: some View {
        Text("Description", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
        
#if os(tvOS)
        TextField(text: $entry.content, prompt: Text("Add content", bundle: .module), axis: .vertical) {
            Text("Description", bundle: .module)
        }
        .frame(minHeight: 120, maxHeight: 200)
        .border(Color.accentColor.secondary)
        .padding(.bottom, 6)
        .focused($currentFocus, equals: .information)
#else
        TextEditorLinkView(model: editModel)
            .focused($currentFocus, equals: .information)
        
#endif
    }
}
