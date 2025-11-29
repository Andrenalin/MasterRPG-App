// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EditGroupEditorList: View {
    let selectedItems: [ItemRowTreeModel]
    let editController: EditGroupController<ItemController, EditController>
    @Binding var isPresented: Bool
    
    @Environment(WeatherRootModel.self) private var root

    var body: some View {
        EditGroupEditor(editGroupController: editController, isPresented: $isPresented) { model in
            MainRow(model: model, isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        }
    }
}
