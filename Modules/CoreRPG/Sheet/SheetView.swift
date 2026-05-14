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
    
    @State private var dropTargetEntryId: UUID?
    
    var body: some View {
        if sheetModel.showHeader || isEditor {
            GameShareView(root: root, model: model) {
                nameRow
            }
            .sheetBorderColor(level: sheetModel.level)
            
            if !sheetModel.isFolded {
                inlineRows
                
                secondaryRow
                    .sheetBorderColor(level: sheetModel.level)
            }
        }
        
        if !sheetModel.isFolded {
            entryRows
        }
        
        endRow
            .onChange(of: rootModel.editorModel.entryId) { previousEntryId, currentEntryId in
                rootModel.update(sheetModel: sheetModel, previousEntryId: previousEntryId, currentEntryId: currentEntryId)
            }
    }
}

private extension SheetView {
    var nameRow: some View {
        HStack {
            if isEditor && sheetModel.canAdd && entryDataEditable != nil {
                SheetEntryAddButton(rootModel: rootModel, parentModel: sheetModel, onlyIcon: true)
            }
            
            LinkHighlightTextView(model: rootModel.linkTextModel(for: .item(sheetModel.id), text: sheetModel.name))
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title)
        }
    }
    
    var inlineRows: some View {
        ForEach(sheetModel.inlineEntries) { inlineEntry in
            SheetEntryView(rootModel: rootModel, parentModel: sheetModel, entryModel: inlineEntry, isEditor: isEditor, linkTypes: linkTypes)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    var secondaryRow: some View {
        if let description = rootModel.description(for: sheetModel), !description.isEmpty {
            LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(sheetModel.id), text: description))
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.subheadline)
        }
    }
    
    @ViewBuilder var entryRows: some View {
        ForEach(sheetModel.entries) { entry in
            if !entry.isHidden {
                SheetEntryView(rootModel: rootModel, parentModel: sheetModel, entryModel: entry, isEditor: isEditor, linkTypes: linkTypes)
                    .frame(maxWidth: .infinity, alignment: .leading)
#if !os(tvOS)
                    .applyIf(isEditor) {
                        $0
                            .background(dropTargetEntryId == entry.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .draggable(for: entry.source.typeId, itemId: entry.source.itemId, entryId: entry.source.entryId, name: entry.name.withoutLink(), isMove: true)
                            .dropDestination(for: linkTypes) { items, location in
                                handleDrop(items: items, targetEntry: entry)
                            } isTargeted: { isTargeted in
                                dropTargetEntryId = isTargeted ? entry.id : nil
                            }
                    }
#endif
                
                ForEach(entry.entries) { subEntry in
                    if let root = rootModel.rootController(for: subEntry.source.typeId), subEntry.isShown {
                        SheetView(root: root, rootModel: rootModel, sheetModel: subEntry, isEditor: isEditor, linkTypes: linkTypes)
                            .padding(.leading, 2)
                    }
                }

            }
        }
    }

    func handleDrop(items: [LinkType], targetEntry: SheetModel) -> Bool {
        rootModel.handleDrop(items: items, targetEntry: targetEntry, parentModel: sheetModel)
    }
    
    var endRow: some View {
        Color.accentColor.opacity(0.3)
            .frame(height: 8)
    }
    
    var model: any ItemDataAccessable {
        root.itemControllable.itemOrEmpty(for: sheetModel.source.itemId)
    }
    
    var entryDataEditable: (any EntryDataEditable)? {
        rootModel.entryDataEditable(for: sheetModel.source)
    }
}
