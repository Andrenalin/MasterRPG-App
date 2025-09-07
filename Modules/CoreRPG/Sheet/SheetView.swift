// @copyright André Trettin

import SwiftUI

public struct SheetView: View {
    public init(model: TableSheetModel) {
        self.model = model
    }
    
    let model: TableSheetModel

    public var body: some View {
        if let description = model.description(for: model.sheetModel) {
            LinkHighlightTextView(model: model.linkTextModel(for: .description, text: description))
                .foregroundStyle(.secondary)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        }

        ForEach(model.sheetModel.filteredGroups(for: model.searchText)) { group in

            SheetGroupView(model: model, group: group)
                .font(.body)
                .listRowBackground(rowColor(for: group.level))
                .listRowInsets(EdgeInsets(top: 4, leading: 8 + CGFloat(group.level * 20), bottom: 4, trailing: 8))

            ForEach(group.filteredEntries(for: model.searchText)) { entry in
                SheetEntryView(model: model, entry: entry)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowBackground(Color.secondary.opacity(0.3))
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
    init(model: TableSheetModel, group: SheetGroupModel) {
        self.model = model
        self.group = group
    }
    
    let model: TableSheetModel
    let group: SheetGroupModel

    var body: some View {
        LinkHighlightTextView(model: model.linkTextModel(for: .group(group.id), text: text))
        
        ForEach(group.sheetIds, id: \.self) { sheetId in
            if let sheetModel = model.sheets[sheetId] {
                SheetView(model: sheetModel)
            }
        }
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
    let model: TableSheetModel
    let entry: SheetEntryModel

    var body: some View {
        LinkHighlightTextView(model: model.linkTextModel(for: .entry(entry.id), text: entryText))
    }

    var entryText: String {
        "**" + entry.name + "**: " + entry.value
    }
}
