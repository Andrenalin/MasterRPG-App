// @copyright André Trettin

import SwiftUI

struct SheetView<LinkType: LinkDataTransferable>: View {
    init(root: ItemRootController, rootModel: SheetRootModel, sheetModel: SheetModel, isEditor: Bool = false, linkTypes: LinkType.Type = LinkDiceData.self) {
        self.root = root
        self.rootModel = rootModel
        self.sheetModel = sheetModel
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let rootModel: SheetRootModel
    let sheetModel: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var entryDataEditable: (any EntryDataEditable)?
    
    var body: some View {
        nameRow
        
        inlineRows
        
        secondaryRow
        
        entryRows
    }
}

private extension SheetView {
    var nameRow: some View {
        LinkHighlightTextView(model: rootModel.linkTextModel(for: .name, text: sheetModel.name))
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.title)
    }
    
    var inlineRows: some View {
        ForEach(sheetModel.inlineEntries) { inlineEntry in
            SheetEntryView(rootModel: rootModel, entryModel: inlineEntry, isEditor: isEditor, linkTypes: linkTypes)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(rowColor(for: sheetModel.level))
                }
                .padding(4)
        }
    }
    
    @ViewBuilder
    var secondaryRow: some View {
        if let description = rootModel.description(for: sheetModel), !description.isEmpty {
            LinkHighlightTextView(model: rootModel.linkTextModel(for: .description, text: description))
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(rowColor(for: sheetModel.level))
                }
                .font(.subheadline)
                .padding(4)
        }

        //.moveDisabled(true)
//        if !model.sheetModel.inlineEntries.isEmpty || !description.isEmpty {
//        }
    }
    
    var entryRows: some View {
        ForEach(rootModel.filteredEntries) { entry in
            SheetEntryView(rootModel: rootModel, entryModel: entry, isEditor: isEditor, linkTypes: linkTypes)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(rowColor(for: sheetModel.level))
                }
                .padding(2)
#if !os(tvOS)
                .applyIf(!isEditor) {
                    $0.draggable(for: entry.source.typeId, itemId: entry.source.itemId, entryId: entry.source.entryId, name: entry.name.withoutLink())
                }
#endif
        }
    }
    
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        return .clear
#else
        if level.isMultiple(of: 2) {
            return colorScheme == .dark ? .black : .white
        } else {
            return .secondary.opacity(0.3)
        }
#endif
    }

}
