// @copyright André Trettin


import CoreRPG
import SwiftUI
import DiceRPG
import TableRPG
import CharacterRPG
import MapRPG

struct RootQuickLinkEditor: View {
    let editController: EditController
    
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        @Bindable var model = editController.model
        
        QuickLinkEditor(editController: editController, linkController: root.linkControllable, model: $model.entries, title: model.name) {
            QuickEditorAction(configs: configs, bundle: .module, afterEntries: $0) {
                editController.scan(itemId: model.id, with: $0, module: $1, caseInsensitive: $2, words: $3)
            } selectionView: { selectedIds, module, action in
                switch module {
                case .dice:
                    root.diceRoot.viewController.selectForScan(root: root.diceRoot, ids: selectedIds, dismissAction: action)
                case .table:
                    root.tableRoot.viewController.selectForScan(root: root.tableRoot, ids: selectedIds, dismissAction: action)
                case .value:
                    root.characterRoot.viewController.selectForScan(root: root.characterRoot, ids: selectedIds, dismissAction: action)
                case .map:
                    root.mapRoot.viewController.selectForScan(root: root.mapRoot, ids: selectedIds, dismissAction: action)
                default:
                    root.viewController.selectForScan(root: root, ids: selectedIds, dismissAction: action)
                }
            }
        }
    }

    private var configs: [QuickLinkConfig] {
        [
            QuickLinkConfig(module: .dice, title: "Dice", name: { $0.map { root.diceRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .table, title: "Table", name: { $0.map { root.tableRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .value, title: "Value", name: { $0.map { root.characterRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .map, title: "Map", name: { $0.map { root.mapRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .adventure, title: "Adventure", name: { $0.map { root.linkController.name(for: $0) }.joined(separator: ", ") }),
        ]
    }
}
