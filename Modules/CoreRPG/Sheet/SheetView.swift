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
    
    var body: some View {
        if sheetModel.showHeader || isEditor {
            GameShareView(root: root, model: model) {
                nameRow
            }
            .sheetBorderColor(level: sheetModel.level)

            if !sheetModel.isFolded {
                inlineRows
                    .sheetBorderColor(level: sheetModel.level)

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
            if isEditor && sheetModel.canAdd {
                plusButton
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
    
    var entryRows: some View {
        ForEach(sheetModel.entries) { entry in
            if !entry.isHidden {
                SheetEntryView(rootModel: rootModel, parentModel: sheetModel, entryModel: entry, isEditor: isEditor, linkTypes: linkTypes)
                    .frame(maxWidth: .infinity, alignment: .leading)
#if !os(tvOS)
                    .applyIf(!isEditor) {
                        $0.draggable(for: entry.source.typeId, itemId: entry.source.itemId, entryId: entry.source.entryId, name: entry.name.withoutLink())
                    }
#endif
            }
        }
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
    
    @ViewBuilder var plusButton: some View {
        if entryDataEditable != nil {
            Button(action: addNewEntry) {
                Label {
                    Text("Add Entry", bundle: .module)
                } icon: {
                    Image(systemName: "note.text.badge.plus")
                        .imageScale(.large)
                        .foregroundStyle(.foreground, .tint)
                }
                .labelStyle(.iconOnly)
            }
            .borderLessTVBottonStyle()
            .padding(4)
            .contentShape(.circle)
            .glassEffectAll()
        }
    }
    
    func addNewEntry() {
        var entryId: UUID?
        withAnimation {
            entryId = rootModel.addNewEntry(in: sheetModel)
        } completion: {
            rootModel.setScrollEntryId(source: sheetModel.source, entryId: entryId)
        }
    }
}

extension View {
    func sheetBorderColor(level: Int) -> some View {
        self.modifier(SheetBorderViewModifier(level: level))
    }
}


struct SheetBorderViewModifier: ViewModifier {
    let level: Int
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(rowColor(for: level))
            }
    }
    
    func rowColor(for level: Int) -> Color {
        if level.isMultiple(of: 2) {
            return .secondary.opacity(0.2)
        } else {
            return .secondary.opacity(0.4)
        }
    }
}
