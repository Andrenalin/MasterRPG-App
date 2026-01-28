// @copyright André Trettin

import SwiftUI

struct InlineEditorView: View {
    let entry: SheetModel
    
    @State private var selectedValue: Bool = false
    
    var body: some View {
        switch entry.editType {
        case .none:
            EmptyView()
        case .number:
            InlineQuickEditView(itemId: entry.source.itemId, preopen: false, layoutDown: false)
                .zIndex(2)
        case .decimal:
            InlineQuickEditView(itemId: entry.source.itemId, preopen: false, layoutDown: false)
                .zIndex(2)
        case .selection:
            selectionEditor
        case .text:
            EmptyView()
        }
    }
    
    private var selectionEditor: some View {
        Toggle(isOn: $selectedValue) {
            Label { Text("Selected", bundle: .module) } icon: { Image(systemName: "checkmark.square") }
        }
        .labelsHidden()
        .tint(Color.accentColor)
        .toggleStyle(.automatic)
        .fixedSize(horizontal: true, vertical: true)
    }
}

#Preview {
    HStack {
        InlineEditorView(entry: SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .value), editType: .selection, name: "Kletter As", description: "I", entries: []))
        
        Text("Kletter As")
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    InlineEditorView(entry: SheetModel(source: ItemRowModel(itemId: UUID(), typeId: .value), editType: .selection, name: "Kletter Off", description: "", entries: []))
}
