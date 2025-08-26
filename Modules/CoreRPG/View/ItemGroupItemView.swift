// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemGroupItemView: View {
    public init(model: ItemDataModel) {
        self.model = model
    }
    let model: ItemDataModel

    @Environment(\.modelContext) var modelContext
    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        VStack {
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: item.category.icon)
                .imageScale(.large)
                .
            font(.title)
        }
        .frame(width: 128)
        .padding()
    }

    var item: ItemDataModel {
        guard let id = selection.selectedItem else { return model }
        return ItemDataModel.model(modelContext: modelContext, id: id) ?? model
    }
}
