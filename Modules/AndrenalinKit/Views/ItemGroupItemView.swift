// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemGroupItemView<Model: ItemDataAccessable>: View {
    public init(root: any ItemRootControllable, model: Model) {
        self.root = root
        self.model = model
    }
    
    let root: any ItemRootControllable
    let model: Model

    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        VStack {
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: root.module.icon)
                .imageScale(.large)
                .font(.title)
        }
        .frame(width: 128)
        .padding()
    }

    var item: Model {
        guard let id = selection.selectedItem else { return model }
        return root.itemControllable.itemSync(for: id) as? Model ?? model
    }
}
