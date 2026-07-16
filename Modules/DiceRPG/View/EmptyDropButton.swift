// @copyright André Trettin

import CoreRPG
import SwiftUI

struct EmptyDropButton: View {
    let selectionModel: ItemSelectionModel

    @Environment(DiceRootModel.self) private var root
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Button {
            root.itemSelectionModel = selectionModel
#if os(macOS)
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.dice.linkWindowId))
#else
            // We need the module-specific route because generic selection does not update this model.
            navigator.navigate(to: SelectionRoute.selection, method: .managedSheet)
#endif
        } label: {
            VStack {
                if appSizeModel.mode == .regular {
                    Text("Drop \(root.configurable.module.title)", bundle: .module)

                    Image(systemName: "square.and.arrow.down")
                        .imageScale(.large)
                }
                Text(chooseText, bundle: .module)
            }
            .padding(.horizontal, 12)
        }
        .contentShape(.rect)
    }

    private var chooseText: LocalizedStringKey {
#if os(macOS)
        "Open \(root.configurable.module.title)"
#else
        "Choose \(root.configurable.module.title)"
#endif
    }
}

#Preview(traits: .mockData) {
    EmptyDropButton(selectionModel: ItemSelectionModel())
        .environment(AppWindowSizeModel())
        .environment(ScenesManager())
}
