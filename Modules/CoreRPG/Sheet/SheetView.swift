// @copyright André Trettin

import SwiftUI

public struct SheetView<LinkType: LinkDataTransferable>: View {
    public init(root: ItemRootController, model: TableSheetModel, isEditor: Bool = false, linkTypes: LinkType.Type = LinkDiceData.self) {
        self.root = root
        self.model = model
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        if let entryDataEditable, model.sheetModel.sheetType == .edit {
            InlineEditorView(entryDataEditable: entryDataEditable, model: model, entry: model.sheetModel)
        } else {
            if model.sheetModel.showHeader || isEditor {
                HStack {
                    if isEditor && model.sheetModel.canAdd {
                        plusButton
                    }
                    
                    LinkHighlightTextView(model: model.linkTextModel(for: .name, text: model.sheetModel.name))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if isEditor && model.sheetModel.canAdd {
                        dropButton
                            .dropDestination(for: model.sheetModel.source.typeId, isEnabled: isEditor) { name, itemId, entryId in
                                guard let entryDataEditable else { return }
                                if let entryId  {
                                    withAnimation {
                                        let isMoved = entryDataEditable.move(itemId: itemId, entryId: entryId, into: model.sheetModel.source)
                                        if isMoved {
                                            model.move(itemId: itemId, entryId: entryId, into: model.sheetModel.source)
                                        }
                                    }
                                }
                            }
                    }
                }
                .contentShape(.rect)
                .font(.title)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .moveDisabled(true)
                
                if !model.sheetModel.inlineEntries.isEmpty || model.description(for: model.sheetModel)?.isEmpty ?? false {
                    VStack(alignment: .leading) {
                        if let description = model.description(for: model.sheetModel) {
                            LinkHighlightTextView(model: model.linkTextModel(for: .description, text: description))
                        }
                        ForEach(model.sheetModel.inlineEntries) { inlineEntry in
                            SheetEntryView(root: root, model: model, entry: inlineEntry, isEditor: isEditor, linkTypes: linkTypes)
                        }
                    }
                    .font(.subheadline)
                    .listRowBackground(rowColor(for: model.sheetModel.level))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .moveDisabled(true)
                }
            }
            
            ForEach(model.sheetModel.filter(searchText: model.searchText)) { entry in
                SheetEntryView(root: root, model: model, entry: entry, isEditor: isEditor, linkTypes: linkTypes)
                //                .draggable(LinkEntryData(itemId: entry.source.itemId, entryId: entry.source.entryId, name: entry.name, module: entry.source.typeId))
            }
            .applyIf(isEditor) {
                $0.onMove { indexSet, index in
                    guard let entryDataEditable else { return }
                    if entryDataEditable.move(itemId: model.sheetModel.source.itemId, entryFrom: indexSet, to: index) {
                        model.move(itemId: model.sheetModel.source.itemId, indexSet: indexSet, to: index)
                    }
                }
            }
            .onChange(of: root.editControllable.editorModel.currentEntryId) { previousEntryId, _ in
                guard let previousEntryId, root.editControllable.editorModel.currentItemId == model.itemId else { return }
                withAnimation { model.update(entryId: previousEntryId) }
            }
        }
        
        Color.accentColor.opacity(0.3)
            .frame(height: 8)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        
            .onChange(of: model.searchText) {
                withAnimation { model.updateSearch() }
            }
    }
    
    var entryDataEditable: (any EntryDataEditable)? {
        root.editControllable as? (any EntryDataEditable)
    }
    
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
    
    @ViewBuilder var plusButton: some View {
        if let entryDataEditable {
            Button {
                withAnimation {
                    let entryId = entryDataEditable.addNewEntry(itemId: model.sheetModel.source.itemId)
                    root.editControllable.setCurrentItem(to: ItemRowTreeModel(itemId: model.sheetModel.source.itemId, entryId: entryId, typeId: root.configurable.module))
                    root.editControllable.editorModel.currentEntryId = entryId
                    model.add(entryId: entryId)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.25))
                        root.editControllable.editorModel.scrollEntryId = entryId
                    }
                }
            } label: {
                Image(systemName: "note.text.badge.plus")
                    .imageScale(.large)
                    .foregroundStyle(.foreground, .tint)
            }
            .borderLessTVBottonStyle()
            .padding(4)
            .contentShape(.circle)
#if !os(visionOS)
            .glassEffect()
#endif
        }
    }
    
    @ViewBuilder var dropButton: some View {
        if entryDataEditable != nil {
            Image(systemName: "square.and.arrow.down.on.square")
                .imageScale(.large)
                .foregroundStyle(.foreground, .tint)
                .padding(4)
                .contentShape(.circle)
#if !os(visionOS)
                .glassEffect()
#endif
        }
    }
}
