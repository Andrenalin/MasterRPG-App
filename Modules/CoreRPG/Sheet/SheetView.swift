// @copyright André Trettin

import SwiftUI

public struct SheetView: View {
    public init(root: ItemRootController, model: TableSheetModel, isEditor: Bool = false) {
        self.root = root
        self.model = model
        self.isEditor = isEditor
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    let isEditor: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    public var body: some View {
        if model.sheetModel.showHeader {
            LinkHighlightTextView(model: model.linkTextModel(for: .name, text: model.sheetModel.name))
                .font(.title)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            
            if let description = model.description(for: model.sheetModel), !description.isEmpty {
                LinkHighlightTextView(model: model.linkTextModel(for: .description, text: description))
                    .font(.subheadline)
                    .listRowBackground(rowColor(for: model.sheetModel.level))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
        }
        
        ForEach(model.sheetModel.filter(searchText: model.searchText)) { entry in
            SheetGroupView(root: root, model: model, entry: entry, isEditor: isEditor)
        }
        .onChange(of: model.searchText) {
            withAnimation { model.updateSearch() }
        }
    }
    
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
}

struct SheetGroupView: View {
    init(root: ItemRootController, model: TableSheetModel, entry: SheetModel, isEditor: Bool) {
        self.root = root
        self.model = model
        self.entry = entry
        self.isEditor = isEditor
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    let entry: SheetModel
    let isEditor: Bool
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
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
                    default:
                        EmptyView()
                    }
                }
                
                if isEditor && entry.sheetType == .item {
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
        .onTapGesture(count: 2) {
            withAnimation { root.editControllable.editorModel.currentEntryId = entry.source.entryId }
        }
        
        ForEach(entry.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(root: root, model: sheetModel, isEditor: isEditor)
            }
        }
    }
}

private extension SheetGroupView {
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
