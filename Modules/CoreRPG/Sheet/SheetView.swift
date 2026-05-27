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
    
    @State private var dropTargetEntryId: String?
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        if sheetModel.showHeader || isEditor {
            GameShareView(root: root, itemId: sheetModel.source.itemId) {
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
                guard previousEntryId != currentEntryId else { return }
                rootModel.update(sheetModel: sheetModel, previousEntryId: previousEntryId, currentEntryId: currentEntryId)
            }
    }
}

private extension SheetView {
    var nameRow: some View {
        HStack {
            if isEditor && sheetModel.canAdd {
                SheetEntryAddButton(rootModel: rootModel, parentModel: sheetModel, onlyIcon: true)
            }
            
            LinkHighlightTextView(model: rootModel.linkTextModel(for: .item(sheetModel.source.itemId), text: sheetModel.name))
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.title)
        }
    }
    
    var inlineRows: some View {
        ForEach(sheetModel.inlineEntries) { inlineEntry in
            // Display inline entries directly without SheetEntryView wrapper
            // to avoid triggering beforeInline/afterInline recursion
            Group {
                viewController(for: inlineEntry.source)?.rowViewer(source: inlineEntry.source, destination: inlineEntry.destination)
            }
            .applyIf(inlineEntry.sheetType == .photo) {
                $0.frame(height: 160)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .applyIf(inlineEntry.sheetType != .photo) {
                $0.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    func viewController(for source: ItemRowModel) -> ViewControllable? {
        rootModel.rootController(for: source.typeId)?.viewControllable
    }
    
    @ViewBuilder
    var secondaryRow: some View {
        if let description = rootModel.description(for: sheetModel), !description.isEmpty {
            LinkHighlightTextView(model: rootModel.linkTextModel(for: .entry(sheetModel.source.entryId ?? sheetModel.source.itemId), text: description))
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
}
