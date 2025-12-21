// @copyright André Trettin

import SwiftUI

public struct SheetView: View {
    public init(root: ItemRootController, model: TableSheetModel) {
        self.root = root
        self.model = model
    }
    
    let root: ItemRootController
    let model: TableSheetModel

    public var body: some View {
        if let description = model.description(for: model.sheetModel), !description.isEmpty {
            LinkHighlightTextView(model: model.linkTextModel(for: .description, text: description))
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
               // .listRowBackground(rowColor(for: group.level))
        }

        ForEach(model.sheetModel.filter(searchText: model.searchText)) { entry in
            SheetGroupView(root: root, model: model, group: entry)
        }
        .onChange(of: model.searchText) {
            withAnimation { model.updateSearch() }
        }
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
    
    var body: some View {
        LinkHighlightTextView(model: model.linkTextModel(for: .entry(group.id), text: text, shareResults: shareResult))
            .font(.body)
            .listRowBackground(rowColor(for: group.level))
            .listRowInsets(EdgeInsets(top: 8, leading: 8 + CGFloat(group.level * 4), bottom: 8, trailing: 8))

        ForEach(group.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(root: root, model: sheetModel)
            }
        }
    }
    
    func rowColor(for level: Int) -> Color {
        level.isMultiple(of: 2) ? .clear : .secondary.opacity(0.5)
    }

    
    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: group.source.itemId, childId: group.source.entryId, module: group.source.typeId), showGame: showGame, gameModus: gameModus)
    }

    
    var text: String {
        if group.description.isEmpty {
            group.name
        } else {
            "**" + group.name + "**: " + group.description
        }
    }
}
