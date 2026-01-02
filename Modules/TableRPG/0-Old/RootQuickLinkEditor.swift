// @copyright André Trettin

import CoreRPG
import SwiftUI
import DiceRPG

struct RootQuickLinkEditor: View {
    let editController: EditController
    let model: TableModel
    
    @Environment(TableRootModel.self) private var root

    var body: some View {
        @Bindable var model = model
        return QuickLinkEditor(editController: editController, linkController: root.rootControllable.linkControllable, model: $model.entries, title: model.name) { _ in
//            QuickEditorAction(configs: configs, bundle: .module, afterEntries: $0) { _,_,_,_ in
//                //editController.scan(itemId: model.id, with: $0, module: $1, caseInsensitive: $2, words: $3)
//            } selectionView: { selectedIds, module, action in
//                switch module {
//                    case .dice:
//                        root.diceRoot.viewController.selectForScan(root: root.diceRoot, ids: selectedIds, dismissAction: action)
//                    default:
//                    root.viewController.selectForScan(root: root, ids: selectedIds, dismissAction: action)
//                }
//            }
        }
    }
    
    private var configs: [QuickLinkConfig] {
        [
            QuickLinkConfig(module: .dice, title: "Dice", name: { $0.map { root.diceRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .table, title: "Table", name: { $0.map { root.linkController.name(for: $0) }.joined(separator: ", ") }),
        ]
    }
}
