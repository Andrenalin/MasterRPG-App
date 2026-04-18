// @copyright André Trettin

import SwiftUI

public struct SheetView<LinkType: LinkDataTransferable>: View {
    public init(root: ItemRootController, model: SheetRootModel, isEditor: Bool = false, linkTypes: LinkType.Type = LinkDiceData.self) {
        self.root = root
        self.model = model
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let model: SheetRootModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var entryDataEditable: (any EntryDataEditable)?
    
    public var body: some View {
        LinkHighlightTextView(model: model.linkTextModel(for: .name, text: model.sheetModel.name))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
//        if model.isAtMaxDepth {
//            // Maximum nesting depth reached - show fallback
//            Text("Maximum nesting depth reached", bundle: .module)
//                .foregroundStyle(.secondary)
//                .italic()
//                .font(.caption)
//                .frame(maxWidth: .infinity, alignment: .leading)
//        } else if let entryDataEditable, model.sheetModel.sheetType == .edit {
//            InlineEditorView(entryDataEditable: entryDataEditable, model: model, entry: model.sheetModel)
//        } else {
//            if model.sheetModel.showHeader || isEditor {
//                HStack {
//                    if isEditor && model.sheetModel.canAdd {
//                        plusButton
//                    }
//                    
//                    LinkHighlightTextView(model: model.linkTextModel(for: .name, text: model.sheetModel.name))
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                    
//                    if isEditor && model.sheetModel.canAdd {
//                        dropButton
//                            .dropDestination(for: model.sheetModel.source.typeId, isEnabled: isEditor) { name, itemId, entryId in
//                                if let entryId  {
//                                    withAnimation {
//                                        let isMoved = model.moveItem(itemId: itemId, entryId: entryId, into: model.sheetModel.source)
//                                        if isMoved {
//                                            model.move(itemId: itemId, entryId: entryId, into: model.sheetModel.source)
//                                            model.updateParent()
//                                        }
//                                    }
//                                }
//                            }
//                    }
//                }
//                .contentShape(.rect)
//                .font(.title)
//                .listRowBackground(Color.clear)
//                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
//                .moveDisabled(true)
//                
//                if !model.sheetModel.inlineEntries.isEmpty || !(model.description(for: model.sheetModel)?.isEmpty ?? true) {
//                    VStack(alignment: .leading) {
//                        if let description = model.description(for: model.sheetModel), !description.isEmpty {
//                            LinkHighlightTextView(model: model.linkTextModel(for: .description, text: description))
//                        }
//                        ForEach(model.sheetModel.inlineEntries) { inlineEntry in
//                            SheetFirstEntryView(model: model, entry: inlineEntry, isEditor: isEditor, linkTypes: linkTypes)
//                        }
//                    }
//                    .font(.subheadline)
//                    .listRowBackground(rowColor(for: model.sheetModel.level))
//                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
//                    .moveDisabled(true)
//                }
//            }
//            
//            ForEach(model.filteredEntries) { entry in
//                SheetFirstEntryView(model: model, entry: entry, isEditor: isEditor, linkTypes: linkTypes)
//#if !os(tvOS)
//                    .applyIf(!isEditor) {
//                        $0.draggable(for: entry.source.typeId, itemId: entry.source.itemId, entryId: entry.source.entryId, name: entry.name.withoutLink())
//                    }
//#endif
//            }
//            .applyIf(isEditor) {
//                $0.onMove { indexSet, index in
//                    model.moveEntries(indexSet: indexSet, to: index)
//                }
//            }
//            .onChange(of: model.getCurrentEntryId(for: model.sheetModel.source)) { previousEntryId, newEntryId in
//                if let previousEntryId, model.getCurrentItemId(for: model.sheetModel.source) == model.itemId {
//                    withAnimation { model.update(entryId: previousEntryId) }
//                }
//                if let newEntryId, !model.hasEntry(entryId: newEntryId) {
//                    model.updateParent()
//                }
//            }
//            .onChange(of: model.getItemName(for: model.sheetModel.source)) {
//                model.reset()
//            }
//            .onChange(of: model.getItemDescription(for: model.sheetModel.source)) {
//                model.reset()
//            }
//        }
//        
//        Color.accentColor.opacity(0.3)
//            .frame(height: 8)
//            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
//            .listRowBackground(Color.clear)
//            .task(id: model.sheetModel.source) {
//                entryDataEditable = model.entryDataEditable(for: model.sheetModel.source)
//            }
//    }

//    func rowColor(for level: Int) -> Color {
//        #if os(macOS) || os(visionOS)
//        return .clear
//        #else
//        if level.isMultiple(of: 2) {
//            return colorScheme == .dark ? .black : .white
//        } else {
//            return .secondary.opacity(0.3)
//        }
//        #endif
//    }

//    func addNewEntry() {
//        guard let entryId = model.addNewEntry(to: model.sheetModel.source) else { return }
//        withAnimation {
//            model.setCurrentItem(source: model.sheetModel.source, entryId: entryId)
//            model.setCurrentEntryId(source: model.sheetModel.source, entryId: entryId)
//            model.add(entryId: entryId)
//            model.updateParent()
//        } completion: {
//            model.setScrollEntryId(source: model.sheetModel.source, entryId: entryId)
//        }
//    }
//    
//    @ViewBuilder var plusButton: some View {
//        if entryDataEditable != nil {
//            Button(action: addNewEntry) {
//                Label {
//                    Text("Add Entry", bundle: .module)
//                } icon: {
//                    Image(systemName: "note.text.badge.plus")
//                        .imageScale(.large)
//                        .foregroundStyle(.foreground, .tint)
//                }
//                .labelStyle(.iconOnly)
//            }
//            .borderLessTVBottonStyle()
//            .padding(4)
//            .contentShape(.circle)
//            .glassEffectAll()
//        }
//    }
//    
//    @ViewBuilder var dropButton: some View {
//        if entryDataEditable != nil {
//            Label {
//                Text("Drop Here", bundle: .module)
//            } icon: {
//                Image(systemName: "square.and.arrow.down.on.square")
//                    .imageScale(.large)
//                    .foregroundStyle(.foreground, .tint)
//            }
//            .labelStyle(.iconOnly)
//        }
//    }
//}
