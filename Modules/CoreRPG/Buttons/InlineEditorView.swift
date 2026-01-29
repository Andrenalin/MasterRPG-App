// @copyright André Trettin

import SwiftUI

struct InlineEditorView: View {
    let entryDataEditable: (any EntryDataEditable)
    let model: TableSheetModel
    let entry: SheetModel
    
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
            let newValue = entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId)
            withAnimation { textValue <=> newValue }
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
        textValue <=> entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId)
        withAnimation { model.reset() }
    }
    
    var selectionEditor: some View {
        Toggle(isOn: $selectedValue) {
            Label { Text("Selected", bundle: .module) } icon: { Image(systemName: "checkmark.square") }
        }
        .labelsHidden()
        .tint(Color.accentColor)
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
        //.foregroundStyle(.white)
        .labelsHidden()
        //.textFieldStyle(.plain)
        .submitLabel(.return)
        .onSubmit {
            textValue = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            entryDataEditable.updateValue(itemId: entry.source.itemId, entryId: entry.source.entryId, value: textValue)
            withAnimation { model.reset() }
        }
        //.rowEditColor()
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
