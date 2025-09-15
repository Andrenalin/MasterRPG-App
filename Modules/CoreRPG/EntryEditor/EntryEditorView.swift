// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public struct EntryEditorView<Controller: EntryEditControllable>: View {
    public init(entryEditController: Controller, model: Controller.EditDataModel) {
        self.entryEditController = entryEditController
        self.model = model
        self._editModel = State(wrappedValue: TextEditModel(linkRegisterController: entryEditController.editControllable.linkRegisterController, text: ""))
    }
    
    let entryEditController: Controller
    let model: Controller.EditDataModel
    
    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?

    @State private var editModel: TextEditModel

    public var body: some View {
        Group {
            if isActive {
                content(entry: entry)
                    .onAppear {
                        editModel.text = entry.content
                        editModel.resetAttributedText()
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
        .background {
            Rectangle().fill(backGroundColor.gradient.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            entryEditController.editorModel.currentEntryId = nil
        }
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
//        TextEditor(text: $entry.content)
//            .frame(minHeight: 120, maxHeight: 200)
//            .border(Color.accentColor.secondary)
//            .padding(.bottom, 6)
            .focused($currentFocus, equals: .information)
        
#endif
    }
    
    var entry: Controller.EditDataModel.DataModel {
        model[entryEditController.editorModel.currentEntryId ?? UUID()]
    }
}

