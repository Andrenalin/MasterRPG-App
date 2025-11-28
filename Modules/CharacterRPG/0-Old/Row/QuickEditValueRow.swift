// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct QuickEditValueRow: View {
    init(root: CharacterRootModel, editController: EditController, itemId: UUID, entryId: UUID) {
        self.root = root
        self.editController = editController
        self.itemId = itemId
        self.entryId = entryId
        
        let model = root.itemController.itemOrEmpty(for: itemId)
        let controller = LinkReplaceController(getter: { model[entryId].value }, setter: { editController.updateValue(itemId: itemId, entryId: entryId, value: $0) })
        
        self._linkReplacment = State(wrappedValue: controller)
    }
    
    let root: CharacterRootModel
    let editController: EditController
    let itemId: UUID
    let entryId: UUID
    
    @State private var linkReplacment: LinkReplaceController
    @State private var showRemoveAlert = false
    
    var body: some View {
        @Bindable var model = root.itemController.itemOrEmpty(for: itemId)
        VStack(alignment: .leading, spacing: 8) {
            actionBarView
            
            switch valueType {
            case .number:
                textFieldEditor(text: textValue)
                QuickEditorIntView(number: numberValue)
            case .decimal:
                textFieldEditor(text: textValue)
                QuickEditorDoubleView(number: decimalValue)
            case .selection:
                selectionEditor
            default:
                textFieldEditor(text: textValue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .environment(\.gameModus, .edit)
        .alert(alertTitle, isPresented: $showRemoveAlert) {
            Button(role: .destructive) {
                withAnimation {
                    editController.remove(entryId: entryId, at: itemId)
                }
            } label: {
                Label {
                    Text("Remove", bundle: .module)
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("Do you really want to remove the whole entry?", bundle: .module)
        }
    }
}

private extension QuickEditValueRow {
    var valueType: ValueEntryModel.ValueType {
        root.itemController.itemOrEmpty(for: itemId)[entryId].type
    }
    
    var alertTitle: String {
        "Remove Entry".localizedString
    }
    
    var selectedValue: Binding<Bool> {
        Binding {
            root.itemController.itemOrEmpty(for: itemId)[entryId].valueSelected
        } set: { _ in
            withAnimation { editController.toggleSelected(itemId: itemId, entryId: entryId) }
        }
    }
    
    var numberValue: Binding<Int> {
        Binding {
            root.itemController.itemOrEmpty(for: itemId)[entryId].valueNumber
        } set: { newValue in
            withAnimation { editController.updateNumber(itemId: itemId, entryId: entryId, value: newValue) }
        }
    }
    
    var decimalValue: Binding<Double> {
        Binding {
            root.itemController.itemOrEmpty(for: itemId)[entryId].valueDecimal
        } set: { newValue in
            withAnimation { editController.updateDecimal(itemId: itemId, entryId: entryId, value: newValue) }
        }
    }
    
    var textValue: Binding<String> {
        linkReplacment.editValue
    }
    
    var selectionEditor: some View {
        Toggle(isOn: selectedValue) {
            Label { Text("Selected", bundle: .module) } icon: { Image(systemName: "checkmark.square") }
        }
        .tint(Color.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func textFieldEditor(text: Binding<String>) -> some View {
        TextField(text: text) {
            Text("Value", bundle: .module)
        }
#if os(iOS)
        .autocapitalization(.none)
        .textContentType(.name)
        .applyIf(valueType == .number || valueType == .decimal) { content in
            content
                .keyboardType(.numbersAndPunctuation)
        }
#endif
        .disableAutocorrection(true)
        .foregroundStyle(.white)
        .labelsHidden()
        .textFieldStyle(.plain)
        .submitLabel(.return)
        .onSubmit {
            text.wrappedValue = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .rowEditColor()
    }
    
    var actionBarView: some View {
        removeEntryView
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var selectedType: Binding<ValueEntryModel.ValueType> {
        Binding {
            valueType
        } set: { newValue in
            withAnimation { editController.toggleType(itemId: itemId, entryId: entryId, updatedValue: newValue) }
        }
    }
    
    var removeEntryView: some View {
        Button(role: .destructive) {
            withAnimation {
                showRemoveAlert.toggle()
            }
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.red)
        }
        .borderLessTVBottonStyle(notMac: true)
        .contentShape(Rectangle())
        .padding(.leading)
    }
}

#Preview {
    VStack {
        QuickEditValueRow(root: CharacterRootModel.preview, editController: .preview, itemId: ValueModel.previewId, entryId: ValueEntryModel.previewId)
            .environment(CharacterRootModel.preview)
            .environment(\.colorScheme, .dark)
    }
    .padding()
    .background(.secondary)
}
