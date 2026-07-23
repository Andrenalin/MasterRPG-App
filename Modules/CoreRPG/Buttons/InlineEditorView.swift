// @copyright André Trettin

import SwiftUI

struct InlineEditorView: View {
    let entryDataEditable: (any EntryDataEditable)
    let updateHandler: (String) -> Void
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
            withAnimation {
                textValue <=> entryDataEditable.entryValue(itemId: entry.source.itemId, entryId: entry.source.entryId)
                doubleValue <=> entryDataEditable.entryValueAsDecimal(itemId: entry.source.itemId, entryId: entry.source.entryId)
                intValue <=> entryDataEditable.entryValueAsNumber(itemId: entry.source.itemId, entryId: entry.source.entryId)
                selectedValue <=> entryDataEditable.entryValueAsSelected(itemId: entry.source.itemId, entryId: entry.source.entryId)
            }
        }
        .onChange(of: selectedValue) {
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    selected: selectedValue
                )
            }
        }
        .onChange(of: intValue) {
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    number: intValue
                )
            }
        }
        .onChange(of: doubleValue) {
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    decimal: doubleValue
                )
            }
        }
    }
}

private extension InlineEditorView {
    func updateValue(_ mutation: () -> Void) {
        let previousValue = entryDataEditable.entryValue(
            itemId: entry.source.itemId,
            entryId: entry.source.entryId
        )
        mutation()
        let updatedValue = entryDataEditable.entryValue(
            itemId: entry.source.itemId,
            entryId: entry.source.entryId
        )
        withAnimation {
            textValue <=> updatedValue
        }
        if updatedValue != previousValue {
            updateHandler(updatedValue)
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
            updateValue {
                entryDataEditable.updateValue(
                    itemId: entry.source.itemId,
                    entryId: entry.source.entryId,
                    value: textValue
                )
            }
        }
    }
}

#Preview {
    InlineEditorView(
        entryDataEditable: FakeEditController.fake,
        updateHandler: { _ in },
        entry: SheetModel(
            source: ItemRowModel(itemId: .fixture1, entryId: .fixture2, typeId: .none),
            editType: .number,
            name: "Armor Class",
            description: "A deterministic inline editor.",
            entries: []
        )
    )
    .padding()
}
