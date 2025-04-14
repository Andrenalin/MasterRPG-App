// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct EditGroupEditorList: View {
    let selectedItems: [ItemRowTreeModel]
    let editController: EditGroupController<ItemController, EditController>
    @Binding var isPresented: Bool
    
    @Environment(WeatherRoot.self) private var root

    var body: some View {
        EditGroupEditor(editGroupController: editController, isPresented: $isPresented) { model in
            MainRow(model: model, isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        }
    }
}
