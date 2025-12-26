// @copyright André Trettin

import SwiftData
import SwiftUI

public struct ItemGroupItemView: View {
    public init(root: any ItemRootControllable, model: any ItemDataAccessable) {
        self.root = root
        self.model = model
    }
    
    let root: any ItemRootControllable
    let model: any ItemDataAccessable

    @Environment(GroupItemSelectionModel.self) var selection

    public var body: some View {
        VStack {
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: root.configurable.module.icon)
                .imageScale(.large)
                .font(.title)
        }
        .frame(width: 128)
        .padding()
    }

    var item: any ItemDataAccessable {
        guard let id = selection.selectedItem else { return model }
        return root.itemControllable.itemSync(for: id) ?? model
    }
}
