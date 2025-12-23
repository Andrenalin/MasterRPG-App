// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EditGroupEditorList: View {
    let selectedItems: [ItemRowTreeModel]
    let editController: EditGroupController<ItemController, EditController>
    @Binding var isPresented: Bool
    
    @Environment(TableRootModel.self) private var root

    var body: some View {
        EditGroupEditor(editGroupController: editController, isPresented: $isPresented) { model in
            Text("Todo")
        }
    }
}
