// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EditGroupEditorList: View {
    let selectedItems: [ItemRowTreeModel]
    let editController: EditGroupController<ItemController, EditController>
    @Binding var isPresented: Bool
    
    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        EditGroupEditor(editGroupController: editController, isPresented: $isPresented) { model in
            Text(model.name)
            //MainRow(model: model, isSelected: false, cacheItemListModel: editController.cacheItemListModel)
        }
    }
}
