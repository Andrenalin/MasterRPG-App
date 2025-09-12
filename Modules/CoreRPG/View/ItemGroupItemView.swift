// @copyright André Trettin

import SwiftData
import SwiftUI

struct ItemGroupItemView: View {
    let model: ItemDataModel

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        VStack {
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: model.module.icon)
                .imageScale(.large)
                .font(.title)
        }
        .frame(width: 128)
        .padding()
    }

    var item: ItemDataModel {
        guard let id = selection.selectedItem else { return model }
        return ItemDataModel.model(modelContext: modelContext, id: id) ?? model
    }
}
