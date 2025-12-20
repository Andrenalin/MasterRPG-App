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
        }

        ForEach(model.sheetModel.filteredGroups(for: model.searchText)) { group in

            SheetGroupView(root: root, model: model, group: group)
                .font(.body)
                .listRowBackground(rowColor(for: group.level))
                .listRowInsets(EdgeInsets(top: 4, leading: 8 + CGFloat(group.level * 20), bottom: 4, trailing: 8))

            ForEach(group.filteredEntries(for: model.searchText)) { entry in
                SheetEntryView(root: root, model: model, entry: entry)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowBackground(root.module.tint.opacity(0.3))
                    .listRowInsets(EdgeInsets(top: 8, leading: 18 + CGFloat(group.level * 20), bottom: 8, trailing: 8))
            }
        }
        .onChange(of: model.searchText) {
            withAnimation { model.updateSearch() }
        }
    }

    func rowColor(for level: Int) -> Color {
        level.isMultiple(of: 2) ? .clear : .secondary.opacity(0.5)
    }
}

struct SheetGroupView: View {
    init(root: ItemRootController, model: TableSheetModel, group: SheetGroupModel) {
        self.root = root
        self.model = model
        self.group = group
    }
 
    let root: ItemRootController
    let model: TableSheetModel
    let group: SheetGroupModel

    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus
    
    var body: some View {
        LinkHighlightTextView(model: model.linkTextModel(for: .group(group.id), text: text, shareResults: shareResult))
        
        ForEach(group.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(root: root, model: sheetModel)
            }
        }
    }
    
    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: group.id, childId: nil, module: root.module), showGame: showGame, gameModus: gameModus)
    }

    
    var text: String {
        if group.description.isEmpty {
            group.name
        } else {
            "**" + group.name + "**: " + group.description
        }
    }
}

struct SheetEntryView: View {
    let root: ItemRootController
    let model: TableSheetModel
    let entry: SheetEntryModel

    @Environment(\.networkActions) private var networkActions
    @Environment(\.showGame) private var showGame
    @Environment(\.gameModus) private var gameModus

    var body: some View {
        LinkHighlightTextView(model: model.linkTextModel(for: .entry(entry.id), text: entryText, shareResults: shareResult))
    }

    var entryText: String {
        "**" + entry.name + "**: " + entry.value
    }
    
    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: entry.id, childId: nil, module: root.module), showGame: showGame, gameModus: gameModus)
    }

}
