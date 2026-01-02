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
        if model.sheetModel.showHeader {
            LinkHighlightTextView(model: model.linkTextModel(for: .name, text: model.sheetModel.name))
                .font(.title)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .moveDisabled(true)
            
            if let description = model.description(for: model.sheetModel), !description.isEmpty {
                LinkHighlightTextView(model: model.linkTextModel(for: .description, text: description))
                    .font(.subheadline)
                    .listRowBackground(rowColor(for: model.sheetModel.level))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .moveDisabled(true)
            }
        }
        
        ForEach(model.sheetModel.filter(searchText: model.searchText)) { entry in
            SheetGroupView(root: root, model: model, entry: entry, isEditor: isEditor, linkTypes: linkTypes)
        }
        .onMove { indexSet, index in
            entryDataEditable?.move(itemId: model.sheetModel.source.itemId, entryFrom: indexSet, to: index)
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
}

struct SheetGroupView<LinkType: LinkDataTransferable>: View {
    init(root: ItemRootController, model: TableSheetModel, entry: SheetModel, isEditor: Bool, linkTypes: LinkType.Type) {
        self.root = root
        self.model = model
        self.entry = entry
        self.isEditor = isEditor
        self.linkTypes = linkTypes
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    let entry: SheetModel
    let isEditor: Bool
    let linkTypes: LinkType.Type
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if isEditor && entry.sheetType == .item {
                    editButton
                }

                switch entry.sheetType {
                case .item:
                    LinkHighlightTextView(model: model.linkTextModel(for: .entry(entry.id), text: text, shareResults: shareResult))
                        .font(.body)
                        .listRowBackground(rowColor(for: entry.level))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(entry.level * 4), bottom: 8, trailing: 8))
                case .dice:
                    root.viewControllable.rowViewer(source: entry.source)
                case .photo, .space, .weather:
                    root.viewControllable.rowViewer(source: entry.source)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .frame(height: 256)
                case .photoInline:
                    EmptyView()
                }
                
                ForEach(entry.entries) { inlineSheet in
                    switch inlineSheet.sheetType {
                    case .photoInline:
                        root.viewControllable.rowViewer(source: entry.source)
                            .frame(height: 96)
                    default:
                        EmptyView()
                    }
                }
                
                if isEditor && entry.sheetType == .item {
                    deleteButton
                }
            }

            ForEach(entry.entries) { inlineSheet in
                switch inlineSheet.sheetType {
                case .dice:
                    root.viewControllable.rowViewer(source: inlineSheet.source)
                default:
                    EmptyView()
                }
            }
        }
#if !os(tvOS)
        .applyIf(isEditor && entry.sheetType == .item) {
            $0.dropDestination(for: linkTypes, isEnabled: true) { items, sessions in
                guard let editController = root.editControllable as? (any EntryDataEditable), let entryId = entry.source.entryId else { return }
                items.forEach {
                    editController.add(link: $0.name, module: $0.module, itemId: $0.itemId, entryId: $0.entryId, destinationItemId: entry.source.itemId, destinationEntryId: entryId)
                }
            }
        }
#endif

        
        ForEach(entry.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(root: root, model: sheetModel, isEditor: isEditor, linkTypes: linkTypes)
            }
        }
    }
}

private extension SheetGroupView {
    var editButton: some View {
        Button {
            withAnimation {
                root.editControllable.setCurrentItem(to: ItemRowTreeModel(itemId: entry.source.itemId, entryId: entry.source.entryId, typeId: entry.source.typeId))
            }
        } label: {
            Image(systemName: "square.and.pencil")
                .imageScale(.large)
                .foregroundStyle(.foreground, .tint)
        }
        .borderLessTVBottonStyle()
        .contentShape(.circle)
#if !os(visionOS)
        .glassEffect()
#endif
    }

    var deleteButton: some View {
        Button(role: .destructive) {
            withAnimation {
                root.editControllable.removeEntry(source: entry.source)
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.white, .red, .red)
        }
        .borderLessTVBottonStyle()
        .contentShape(.circle)
#if !os(visionOS)
        .glassEffect()
#endif
    }

    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
    
    var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: entry.source.itemId, childId: entry.source.entryId, module: entry.source.typeId), showGame: showGame, gameModus: gameModus)
    }
        
    var text: String {
        if entry.description.isEmpty {
            entry.name
        } else if entry.name.isEmpty {
            entry.description
        } else {
            "**" + entry.name + "**: " + entry.description
        }
    }
}
