// @copyright André Trettin

import SwiftUI

public struct ModuleInspectorView: View {
    public init(rootController: ItemRootController) {
        self.rootController = rootController
    }
    
    let rootController: ItemRootController
        
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if let itemId = rootController.navigationModel.selectedItemId, let item = rootController.itemControllable.itemSync(for: itemId) {
            if item.specialCategory {
                LinkItemRootView(root: rootController, type: .inspector, itemSelectionModel: rootController.itemSelectionModel)
            } else if let editorLinkModel = rootController.inspectorEditorLinkModel, !editorLinkModel.firstRow.isEmpty {
                EditorLinkView(root: rootController, model: item, editorLinkModel: editorLinkModel)
            } else {
                ModuleInspectorNoContentView()
            }
        } else {
            ModuleInspectorNoContentView()
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct ModuleInspectorNoContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Inspector for this item", bundle: .module)
            } icon: {
                Image(systemName: "scope")
            }
        }
    }
}

#Preview {
    ModuleInspectorView(rootController: .fake)
}
