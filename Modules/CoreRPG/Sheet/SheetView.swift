// @copyright André Trettin

import SwiftUI

public struct SheetView: View {
    public init(root: ItemRootController, model: TableSheetModel) {
        self.root = root
        self.model = model
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    
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
            SheetGroupView(root: root, model: model, group: entry)
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
    init(root: ItemRootController, model: TableSheetModel, group: SheetModel) {
        self.root = root
        self.model = model
        self.group = group
    }
    
    let root: ItemRootController
    let model: TableSheetModel
    let group: SheetModel
    
    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        switch group.sheetType {
        case .item:
            LinkHighlightTextView(model: model.linkTextModel(for: .entry(group.id), text: text, shareResults: shareResult))
                .font(.body)
                .listRowBackground(rowColor(for: group.level))
                .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(group.level * 4), bottom: 8, trailing: 8))
        case .dice:
            root.viewControllable.diceRowView(for: group.source.itemId)
        case .photo:
            root.viewControllable.photoRowView(for: group.source.itemId)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .frame(height: 256)
        }

        ForEach(group.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(root: root, model: sheetModel)
            }
        }
    }
    
    func rowColor(for level: Int) -> Color {
#if os(macOS) || os(visionOS)
        .clear
#else
        level.isMultiple(of: 2) ? (colorScheme == .dark ? .black : .white) : .secondary.opacity(0.3)
#endif
    }
    
    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: group.source.itemId, childId: group.source.entryId, module: group.source.typeId), showGame: showGame, gameModus: gameModus)
    }
    
    
    var text: String {
        if group.description.isEmpty {
            group.name
        } else if group.name.isEmpty {
            group.description
        } else {
            "**" + group.name + "**: " + group.description
        }
    }
}
