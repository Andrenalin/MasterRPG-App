// @copyright André Trettin

import SwiftUI

struct InlineEditorView: View {
    let entryDataEditable: (any EntryDataEditable)
    let model: TableFirstSheetModel
    let entry: SheetFirstModel
    
    @State private var selectedValue: Bool = false
    @State private var textValue: String = ""
    
    @State private var intValue: Int = 0
    @State private var doubleValue: Double = 0.0
    
    var body: some View {
        VStack {
            switch entry.editType {
            case .none:
                EmptyView()
            case .number:
                textFieldEditor()
                QuickEditorIntView(number: $intValue)
            case .decimal:
                textFieldEditor()
                QuickEditorDoubleView(number: $doubleValue)
            case .selection:
                selectionEditor
            case .text:
                textFieldEditor()
            }
        }
        .onChange(of: entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId), initial: true) {
            withAnimation {
                textValue <=> entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId)
                doubleValue <=> entryDataEditable.entryValueAsDecimal(itemId: entry.source.itemId, entryId: entry.source.entryId)
                intValue <=> entryDataEditable.entryValueAsNumber(itemId: entry.source.itemId, entryId: entry.source.entryId)
                selectedValue <=> entryDataEditable.entryValueAsSelected(itemId: entry.source.itemId, entryId: entry.source.entryId)
            }
        }
        .onChange(of: selectedValue) {
            entryDataEditable.updateValue(itemId: entry.source.itemId, entryId: entry.source.entryId, selected: selectedValue)
        }
        .onChange(of: intValue) {
            entryDataEditable.updateValue(itemId: entry.source.itemId, entryId: entry.source.entryId, number: intValue)
            updateValue()
        }
        .onChange(of: doubleValue) {
            entryDataEditable.updateValue(itemId: entry.source.itemId, entryId: entry.source.entryId, decimal: doubleValue)
            updateValue()
        }
    }
}

private extension InlineEditorView {
    func updateValue() {
        withAnimation {
            textValue <=> entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId)
            model.updateParent()
        }
    }
    
    var selectionEditor: some View {
        Toggle(isOn: $selectedValue) {
            Label { Text("Selected", bundle: .module) } icon: { Image(systemName: "checkmark.square") }
        }
        .labelsHidden()
        .tint(entryDataEditable.itemControllable.config.module.tint)
        .toggleStyle(.automatic)
        .fixedSize(horizontal: true, vertical: true)
    }
    
    func textFieldEditor() -> some View {
        TextField(text: $textValue) {
            Text("Value", bundle: .module)
        }
#if os(iOS)
        .autocapitalization(.none)
        .textContentType(.name)
        .applyIf(entry.editType == .number || entry.editType == .decimal) { content in
            content
                .keyboardType(.numbersAndPunctuation)
        }
#endif
        .disableAutocorrection(true)
        .labelsHidden()
        .submitLabel(.return)
        .textFieldStyle(.plain)
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.secondary, lineWidth: 1)
        }
        .padding(.horizontal)
        .onSubmit {
            textValue = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            entryDataEditable.updateValue(itemId: entry.source.itemId, entryId: entry.source.entryId, value: textValue)
            updateValue()
        }
    }
}

//#Preview {
//    HStack {
//        InlineEditorView(root: ItemRootController.fake, entry: SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .value), editType: .selection, name: "Kletter As", description: "I", entries: []))
//        
//        Text("Kletter As")
//            .frame(maxWidth: .infinity, alignment: .leading)
//    }
//    
//    InlineEditorView(root: .fake, entry: SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .value), editType: .number, name: "Kletter Off", description: "", entries: []))
//}
