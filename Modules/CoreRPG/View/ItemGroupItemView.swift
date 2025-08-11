// @copyright André Trettin

import SwiftData
import SwiftUI

public typealias ModelType = ItemDataAccessable & ItemDataModelable & ListItemFolderable & PersistentModel

public struct ItemGroupItemView<Model: ModelType>: View {
    public init(model: Model) {
        self.model = model
    }
    let model: Model

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
        .padding()
    }

    var item: Model {
        guard let id = selection.selectedItem else { return model }
        return Model.model(modelContext: modelContext, id: id) ?? model
    }
}
