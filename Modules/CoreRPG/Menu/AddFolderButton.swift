// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddFolderButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions

    /// Ignores a second press while a folder is being created. See CODE_AUDIT_Folder §5.29.
    @State private var isCreating = false

    var body: some View {
        Button {
            guard !isCreating else { return }
            isCreating = true
            Task {
                defer { isCreating = false }
                guard let item = await root.editControllable.addNew(type: .folder) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
                await MasterRPGTips.donateContentOrganized()
                if let rootManager = root.rootManager {
                    MasterRPGTips.refreshEligibility(rootManager: rootManager)
                }
            }
        } label: {
            Label {
                Text("New Folder in \(root.configurable.module.title)", bundle: .module)
            } icon: {
                Image(systemName: EditControllerAddType.folder.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(root.folderListControllable.listDisplayModel.isListMode || isCreating)
    }
}

#Preview {
    AddFolderButton(root: ItemRootController.fake, routeActions: RouteActions { _, _, _ in })
}
#endif
