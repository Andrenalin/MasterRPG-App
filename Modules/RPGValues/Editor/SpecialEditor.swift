// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI
import DiceRPG
import TableRPG

struct SpecialEditor: View {
    let editController: EditController
    
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        Section {
            ViewThatFits {
                HStack {
                    showLinkScannerView
                    Spacer()
                    showQuickEditorView
                }
                
                VStack(alignment: .leading) {
                    showLinkScannerView
                    showQuickEditorView
                }
            }
        } header: {
            VStack {
#if os(macOS)
                Divider()
                    .padding(.top)
#endif
                
                Text("Special Editor", bundle: .module)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    private var showLinkScannerView: some View {
        Button {
            navigator.navigate(to: InternalRoute.linkEditor, method: .cover)
        } label: {
            Label { Text("Quick Links", bundle: .module) } icon: { Image(systemName: "link") }
        }
#if os(iOS) || os(visionOS)
        .borderLessTVBottonStyle()
#endif
    }
    
    @MainActor
    private var showQuickEditorView: some View {
        Button {
            navigator.navigate(to: InternalRoute.quickEditor, method: .cover)
        } label: {
            Label { Text("Quick Editor", bundle: .module) } icon: { Image(systemName: "pencil.and.outline") }
        }
#if os(iOS) || os(visionOS)
        .borderLessTVBottonStyle()
#endif
    }
}

struct RootQuickLinkEditor: View {
    let editController: EditController
    
    @Environment(CharacterRootModel.self) private var root

    var body: some View {
        @Bindable var model = editController.model
        return QuickLinkEditor(editController: editController, linkController: root.rootControllable.linkControllable, model: $model.entries, title: model.name) {
            QuickEditorAction(configs: configs, bundle: .module, afterEntries: $0) {
                editController.scan(itemId: model.id, with: $0, module: $1, caseInsensitive: $2, words: $3)
            } selectionView: { selectedIds, module, action in
                switch module {
                    case .dice:
                        root.diceRoot.viewController.selectForScan(root: root.diceRoot, ids: selectedIds, dismissAction: action)
                    case .table:
                        root.tableRoot.viewController.selectForScan(root: root.tableRoot, ids: selectedIds, dismissAction: action)
                    default:
                        root.viewController.selectForScan(ids: selectedIds, dismissAction: action)
                }
            }
        }
    }
    
    private var configs: [QuickLinkConfig] {
        [
            QuickLinkConfig(module: .dice, title: "Dice", name: { $0.map { root.diceRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .table, title: "Table", name: { $0.map { root.tableRoot.linkController.name(for: $0) }.joined(separator: ", ") }),
            QuickLinkConfig(module: .value, title: "Value", name: { $0.map { root.linkController.name(for: $0) }.joined(separator: ", ") }),
        ]
    }
}

#Preview {
    SpecialEditor(editController: .preview)
        .tint(Color.accentColor)
        .accentColor(.teal)
        .environment(CharacterRootModel.preview)
        .environment(\.locale, .init(identifier: "de"))
}
