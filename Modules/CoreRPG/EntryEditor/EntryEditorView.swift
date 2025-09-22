// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public struct EntryEditorView<Controller: EntryEditControllable>: View {
    public init(entryEditController: Controller, model: Controller.EditDataModel) {
        self.entryEditController = entryEditController
        self.model = model
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: entryEditController.editControllable.linkRegisterController, text: ""))
        self._name = State(wrappedValue: "")
    }
    
    let entryEditController: Controller
    let model: Controller.EditDataModel
    
    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?
    
    @State private var editModel: TextEditModel
    @State private var name: String

    public var body: some View {
        Group {
            if isActive {
                content(entry: entry)
                    .onAppear {
                        editModel.text = entry.content
                        editModel.resetAttributedText()
                        name = entry.name
                    }
            }
        }
        .transition(.scale)
        .animation(.bouncy, value: isActive)
    }
    
    func content(entry: Controller.EditDataModel.DataModel) -> some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button {
                            withAnimation { entryEditController.editorModel.currentEntryId = nil }
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

                    nameSection(entry: entry)
                    
                    contentEditor(entry: entry)
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
        entryEditController.module(for: model.itemId).color
    }
    
    var isActive: Bool {
        entry.entryId == entryEditController.editorModel.currentEntryId
    }
    
    @ViewBuilder
    private func nameSection(entry: Controller.EditDataModel.DataModel) -> some View {
        @Bindable var entry = entry
        
        Text("Name", bundle: .module)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        
        HStack {
            TextField(text: $entry.name, prompt: Text("Enter a name", bundle: .module)) {
                Text("Name", bundle: .module)
            }
            .focused($currentFocus, equals: .name)
            .labelsHidden()
            .textFieldStyle(.plain)
            
            Button {
                withAnimation { entry.name = "" }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .opacity(entry.name.isEmpty ? 0: 1)
            .contentTransition(.symbolEffect(.automatic))
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
    }
    
    @ViewBuilder
    func contentEditor(entry: Controller.EditDataModel.DataModel) -> some View {
        @Bindable var entry = entry
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
    
    var entry: Controller.EditDataModel.DataModel {
        model[entryEditController.editorModel.currentEntryId ?? UUID()]
    }
    
    func save() {
        editModel.resetText()
        withAnimation {
            entryEditController.update(entry: entry, name: name, content: editModel.text)
            entryEditController.editorModel.currentEntryId = nil
        }
    }
}
